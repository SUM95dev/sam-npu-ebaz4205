// SPDX-License-Identifier: GPL-2.0
/*
 * Sam NPU DMAengine proxy for EBAZ4205 bring-up.
 *
 * Device tree node provides dma-names = "tx", "rx" and points at the
 * AXI-DMA MM2S/S2MM channels.
 *
 * Two coherent 4 MiB buffers are mmap'ed to userspace:
 *   offset 0         -> TX/MM2S buffer
 *   offset BUF_BYTES -> RX/S2MM buffer
 *
 * The original synchronous ioctls are retained for simple tests.  The START
 * and WAIT ioctls are the preferred interface for the network server because
 * S2MM must be armed before the NPU starts producing data while MM2S may wait
 * for NPU TREADY.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/version.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/uaccess.h>
#include <linux/completion.h>
#include <linux/mutex.h>
#include <linux/kref.h>
#include <linux/slab.h>

#define BUF_BYTES (4*1024*1024)
#define NPU_DMA_IOC_MAGIC 'N'
#define NPU_DMA_TX        _IOW(NPU_DMA_IOC_MAGIC, 1, unsigned int) /* legacy sync */
#define NPU_DMA_RX        _IOW(NPU_DMA_IOC_MAGIC, 2, unsigned int) /* legacy sync */
#define NPU_DMA_TX_START  _IOW(NPU_DMA_IOC_MAGIC, 3, unsigned int)
#define NPU_DMA_RX_START  _IOW(NPU_DMA_IOC_MAGIC, 4, unsigned int)
#define NPU_DMA_TX_WAIT   _IO(NPU_DMA_IOC_MAGIC, 5)
#define NPU_DMA_RX_WAIT   _IO(NPU_DMA_IOC_MAGIC, 6)
#define NPU_DMA_TX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 7)
#define NPU_DMA_RX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 8)

struct npu_dma {
    struct device *dev;
    struct device *tx_dev, *rx_dev;
    struct kref refs;
    struct mutex tx_op_lock, rx_op_lock;
    bool removed;
    bool quarantined;
    dma_cookie_t tx_cookie, rx_cookie;
    struct dma_chan *tx;
    struct dma_chan *rx;
    void *tx_cpu, *rx_cpu;
    dma_addr_t tx_dma, rx_dma;
    struct miscdevice misc;
    struct completion tx_done;
    struct completion rx_done;
    struct mutex lock;
    bool tx_pending;
    bool rx_pending;
    bool opened;
};

static void dma_done(void *arg)
{
    complete((struct completion *)arg);
}

static int submit_start(struct npu_dma *d, bool tx, unsigned int len)
{
    struct dma_chan *ch = tx ? d->tx : d->rx;
    dma_addr_t addr = tx ? d->tx_dma : d->rx_dma;
    enum dma_transfer_direction dir = tx ? DMA_MEM_TO_DEV : DMA_DEV_TO_MEM;
    struct completion *done = tx ? &d->tx_done : &d->rx_done;
    bool *pending = tx ? &d->tx_pending : &d->rx_pending;
    struct dma_async_tx_descriptor *desc;
    dma_cookie_t cookie;
    int ret;

    if (!ch || !len || len > BUF_BYTES || (len & (tx ? 15u : 3u)))
        return -EINVAL;

    mutex_lock(&d->lock);
    if (*pending) {
        mutex_unlock(&d->lock);
        return -EBUSY;
    }

    reinit_completion(done);
    desc = dmaengine_prep_slave_single(ch, addr, len, dir,
                                      DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
    if (!desc) {
        mutex_unlock(&d->lock);
        return -EIO;
    }

    desc->callback = dma_done;
    desc->callback_param = done;
    cookie = dmaengine_submit(desc);
    ret = dma_submit_error(cookie);
    if (ret) {
        mutex_unlock(&d->lock);
        return ret;
    }

    if (tx) d->tx_cookie = cookie;
    else d->rx_cookie = cookie;
    *pending = true;
    dma_async_issue_pending(ch);
    mutex_unlock(&d->lock);
    return 0;
}

static int wait_one(struct npu_dma *d, bool tx)
{
    struct dma_chan *ch = tx ? d->tx : d->rx;
    struct completion *done = tx ? &d->tx_done : &d->rx_done;
    bool *pending = tx ? &d->tx_pending : &d->rx_pending;
    int ret = 0;

    mutex_lock(&d->lock);
    if (!*pending) {
        mutex_unlock(&d->lock);
        return -EINVAL;
    }
    mutex_unlock(&d->lock);

    if (!wait_for_completion_timeout(done, msecs_to_jiffies(5000))) {
        ret = dmaengine_terminate_sync(ch);
        if (ret) return ret; /* Keep pending: reuse is unsafe until cancellation succeeds. */
        ret = -ETIMEDOUT;
    }

    if (!ret && dma_async_is_tx_complete(ch, tx ? d->tx_cookie : d->rx_cookie, NULL, NULL) != DMA_COMPLETE) {
        ret = dmaengine_terminate_sync(ch);
        if (ret) return ret;
        ret = -EIO;
    }
    mutex_lock(&d->lock);
    *pending = false;
    mutex_unlock(&d->lock);
    return ret;
}


static int cancel_one(struct npu_dma *d, bool tx)
{
    struct dma_chan *ch = tx ? d->tx : d->rx;
    bool *pending = tx ? &d->tx_pending : &d->rx_pending;
    int ret = dmaengine_terminate_sync(ch);
    if (ret) return ret;
    mutex_lock(&d->lock);
    *pending = false;
    mutex_unlock(&d->lock);
    return ret;
}

static int submit_sync(struct npu_dma *d, bool tx, unsigned int len)
{
    int ret = submit_start(d, tx, len);
    if (ret)
        return ret;
    return wait_one(d, tx);
}

static long npu_ioctl_locked(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct miscdevice *m = f->private_data;
    struct npu_dma *d = container_of(m, struct npu_dma, misc);
    unsigned int len = 0;

    switch (cmd) {
    case NPU_DMA_TX:
    case NPU_DMA_RX:
    case NPU_DMA_TX_START:
    case NPU_DMA_RX_START:
        if (copy_from_user(&len, (void __user *)arg, sizeof(len)))
            return -EFAULT;
        break;
    default:
        break;
    }

    switch (cmd) {
    case NPU_DMA_TX:       return submit_sync(d, true, len);
    case NPU_DMA_RX:       return submit_sync(d, false, len);
    case NPU_DMA_TX_START: return submit_start(d, true, len);
    case NPU_DMA_RX_START: return submit_start(d, false, len);
    case NPU_DMA_TX_WAIT:  return wait_one(d, true);
    case NPU_DMA_RX_WAIT:  return wait_one(d, false);
    case NPU_DMA_TX_CANCEL:return cancel_one(d, true);
    case NPU_DMA_RX_CANCEL:return cancel_one(d, false);
    default:               return -ENOTTY;
    }
}

/* Serialize an entire operation per direction. In particular WAIT must not
 * clear a newer START's pending flag after a concurrent CANCEL. TX and RX
 * retain independent locks, so full duplex submission is still possible.
 * A same-direction CANCEL waits for WAIT's bounded five-second timeout. */
static long npu_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct miscdevice *m = f->private_data;
    struct npu_dma *d = container_of(m, struct npu_dma, misc);
    struct mutex *op;
    long ret;
    switch (cmd) {
    case NPU_DMA_TX: case NPU_DMA_TX_START: case NPU_DMA_TX_WAIT: case NPU_DMA_TX_CANCEL:
        op = &d->tx_op_lock; break;
    case NPU_DMA_RX: case NPU_DMA_RX_START: case NPU_DMA_RX_WAIT: case NPU_DMA_RX_CANCEL:
        op = &d->rx_op_lock; break;
    default: return -ENOTTY;
    }
    mutex_lock(op);
    ret = READ_ONCE(d->removed) ? -ENODEV : npu_ioctl_locked(f, cmd, arg);
    mutex_unlock(op);
    return ret;
}

static int npu_mmap(struct file *f, struct vm_area_struct *vma)
{
    struct miscdevice *m = f->private_data;
    struct npu_dma *d = container_of(m, struct npu_dma, misc);
    unsigned long off = vma->vm_pgoff << PAGE_SHIFT;
    size_t len = vma->vm_end - vma->vm_start;

    if (READ_ONCE(d->removed)) return -ENODEV;
    if (len > BUF_BYTES)
        return -EINVAL;
    if (off == 0)
        return dma_mmap_coherent(d->tx_dev, vma, d->tx_cpu, d->tx_dma, BUF_BYTES);
    if (off == BUF_BYTES) {
        /* The userspace offset selects the RX allocation; it is not an offset
         * within that allocation. dma_mmap_coherent() interprets vm_pgoff as
         * an in-allocation page offset, so normalize it to zero temporarily. */
        unsigned long saved_pgoff = vma->vm_pgoff;
        int ret;
        vma->vm_pgoff = 0;
        ret = dma_mmap_coherent(d->rx_dev, vma, d->rx_cpu, d->rx_dma, BUF_BYTES);
        vma->vm_pgoff = saved_pgoff;
        return ret;
    }
    return -EINVAL;
}


static int npu_open(struct inode *inode, struct file *f)
{
    struct miscdevice *m = f->private_data;
    struct npu_dma *d = container_of(m, struct npu_dma, misc);
    int ret = 0;

    mutex_lock(&d->lock);
    if (READ_ONCE(d->removed))
        ret = -ENODEV;
    else if (d->opened)
        ret = -EBUSY;
    else {
        kref_get(&d->refs);
        d->opened = true;
    }
    mutex_unlock(&d->lock);
    return ret;
}

/* The platform owns one reference and an open file owns another. VMAs keep
 * that file alive through close(fd), fork and unbind. Never free coherent
 * buffers or callback storage just because platform remove was called. */
static void npu_destroy(struct kref *ref)
{
    struct npu_dma *d = container_of(ref, struct npu_dma, refs);
    dma_free_coherent(d->tx_dev, BUF_BYTES, d->tx_cpu, d->tx_dma);
    dma_free_coherent(d->rx_dev, BUF_BYTES, d->rx_cpu, d->rx_dma);
    dma_release_channel(d->tx);
    dma_release_channel(d->rx);
    put_device(d->tx_dev);
    put_device(d->rx_dev);
    put_device(d->dev);
    kfree(d);
}

/* A DMA provider that cannot stop a channel must never get its buffers back.
 * Keep one permanent object/module reference on this exceptional path. A board
 * reboot is required; leaking quarantined allocations is preferable to DMA
 * writing into freed memory or running a callback from an unloaded module. */
static void npu_quarantine(struct npu_dma *d)
{
    if (!d->quarantined) {
        d->quarantined = true;
        WRITE_ONCE(d->removed, true);
        kref_get(&d->refs);
        __module_get(THIS_MODULE);
        dev_err(d->dev, "DMA cancellation failed; device quarantined until reboot\n");
    }
}

static int npu_release(struct inode *inode, struct file *f)
{
    struct miscdevice *m = f->private_data;
    struct npu_dma *d = container_of(m, struct npu_dma, misc);

    int tx_ret, rx_ret;

    /* A userspace crash/close must not leave an AXI-DMA descriptor pending,
     * otherwise the next owner would see EBUSY forever.  The device is
     * intentionally single-owner, so terminating both channels is safe here. */
    mutex_lock(&d->tx_op_lock);
    mutex_lock(&d->rx_op_lock);
    tx_ret = dmaengine_terminate_sync(d->tx);
    rx_ret = dmaengine_terminate_sync(d->rx);
    if (tx_ret || rx_ret) npu_quarantine(d);
    mutex_lock(&d->lock);
    d->tx_pending = tx_ret != 0;
    d->rx_pending = rx_ret != 0;
    d->opened = false;
    mutex_unlock(&d->lock);
    mutex_unlock(&d->rx_op_lock);
    mutex_unlock(&d->tx_op_lock);
    kref_put(&d->refs, npu_destroy);
    return tx_ret ? tx_ret : rx_ret;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = npu_open,
    .release = npu_release,
    .unlocked_ioctl = npu_ioctl,
    .mmap = npu_mmap,
};

static int npu_probe(struct platform_device *pdev)
{
    struct npu_dma *d;
    int ret;

    d = kzalloc(sizeof(*d), GFP_KERNEL);
    if (!d)
        return -ENOMEM;
    d->dev = get_device(&pdev->dev);
    kref_init(&d->refs);
    mutex_init(&d->tx_op_lock);
    mutex_init(&d->rx_op_lock);
    init_completion(&d->tx_done);
    init_completion(&d->rx_done);
    mutex_init(&d->lock);

    d->tx = dma_request_chan(&pdev->dev, "tx");
    if (IS_ERR(d->tx)) {
        ret = PTR_ERR(d->tx);
        goto err_struct;
    }
    d->rx = dma_request_chan(&pdev->dev, "rx");
    if (IS_ERR(d->rx)) {
        ret = PTR_ERR(d->rx);
        dma_release_channel(d->tx);
        goto err_struct;
    }
    d->tx_dev = get_device(dmaengine_get_dma_device(d->tx));
    d->rx_dev = get_device(dmaengine_get_dma_device(d->rx));

    d->tx_cpu = dma_alloc_coherent(d->tx_dev, BUF_BYTES, &d->tx_dma, GFP_KERNEL);
    d->rx_cpu = dma_alloc_coherent(d->rx_dev, BUF_BYTES, &d->rx_dma, GFP_KERNEL);
    if (!d->tx_cpu || !d->rx_cpu) {
        ret = -ENOMEM;
        goto err_dma;
    }

    d->misc.minor = MISC_DYNAMIC_MINOR;
    d->misc.name = "npu_dma";
    d->misc.fops = &fops;
    d->misc.parent = &pdev->dev;

    ret = misc_register(&d->misc);
    if (ret)
        goto err_dma;

    platform_set_drvdata(pdev, d);
    dev_info(&pdev->dev, "Sam NPU DMA proxy ready (async start/wait enabled)\n");
    return 0;

err_dma:
    if (d->tx_cpu)
        dma_free_coherent(d->tx_dev, BUF_BYTES, d->tx_cpu, d->tx_dma);
    if (d->rx_cpu)
        dma_free_coherent(d->rx_dev, BUF_BYTES, d->rx_cpu, d->rx_dma);
    dma_release_channel(d->tx);
    dma_release_channel(d->rx);
    put_device(d->tx_dev);
    put_device(d->rx_dev);
err_struct:
    put_device(d->dev);
    kfree(d);
    return ret;
}

static void npu_remove_common(struct platform_device *pdev)
{
    struct npu_dma *d = platform_get_drvdata(pdev);
    /* misc_deregister synchronizes with misc_open; do it before dropping the
     * platform reference. Existing files remain valid but cannot submit work. */
    WRITE_ONCE(d->removed, true);
    misc_deregister(&d->misc);
    mutex_lock(&d->tx_op_lock);
    mutex_lock(&d->rx_op_lock);
    /* No owner/pending transfer means release already synchronized callbacks. */
    if (d->tx_pending || d->rx_pending) {
        int tx_ret = dmaengine_terminate_sync(d->tx);
        int rx_ret = dmaengine_terminate_sync(d->rx);
        if (tx_ret || rx_ret) npu_quarantine(d);
    }
    mutex_unlock(&d->rx_op_lock);
    mutex_unlock(&d->tx_op_lock);
    kref_put(&d->refs, npu_destroy);
}

/* platform_driver::remove changed from int to void in modern kernels.
 * Keep the bring-up driver source buildable both on PetaLinux-era kernels and
 * on current kernels used for source-level validation. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
static void npu_remove(struct platform_device *pdev)
{
    npu_remove_common(pdev);
}
#else
static int npu_remove(struct platform_device *pdev)
{
    npu_remove_common(pdev);
    return 0;
}
#endif

static const struct of_device_id ids[] = {
    { .compatible = "sam,npu-dma-proxy" },
    {}
};
MODULE_DEVICE_TABLE(of, ids);

static struct platform_driver drv = {
    .probe = npu_probe,
    .remove = npu_remove,
    .driver = {
        .name = "npu_dma_proxy",
        .of_match_table = ids,
    },
};
module_platform_driver(drv);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Sam NPU AXI DMA proxy with asynchronous start/wait");
