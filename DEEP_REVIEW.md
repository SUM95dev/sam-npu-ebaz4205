# نتیجهٔ بررسی تکمیلی سورس و منابع

نسخهٔ قبلی را برای پایان بیلد و بررسی لاگ نگه دار. این پوشه نسخهٔ جداگانهٔ بعدی است؛ تغییراتش به بیلدی که همین حالا در سیستم تو اجرا می‌شود منتقل نشده‌اند.

**این گزارش ادعا نمی‌کند تمام فایل‌ها ۲۵ مرتبه از ابتدا تا انتها بررسی انسانی شده‌اند.** بررسی شامل خواندن مسیرهای حساس، lint مستقل تمام ۲۹ ماژول، تست‌های جدیدِ قبل/بعد، کامپایل واقعی ماژول کرنل و تطبیق با منابع اصلی است. زمان یا تعداد دور ساختگی گزارش نشده است.

## اصلاحات تازه نسبت به 20ROUND_REVIEW

1. **درایور DMA — هم‌زمانی:** عملیات هر کانال با mutex مستقل سری می‌شود. دو WAIT هم‌زمان دیگر نمی‌توانند وضعیت یک انتقال تازه را پاک کنند. TX و RX همچنان مستقل‌اند. CANCEL همان کانال ممکن است تا پایان timeout پنج‌ثانیه‌ای WAIT منتظر قفل بماند.
2. **درایور DMA — طول‌عمر:** ساختار و بافرها با پایان remove آزاد نمی‌شوند اگر فایل یا mapping هنوز زنده است. kref، مرجع فایل و مرجع device از آزادسازی زودهنگام جلوگیری می‌کنند. فایل‌های باز پس از remove اجازهٔ ioctl جدید ندارند. این پشتیبانی از remove خود proxy است؛ حذف هم‌زمان کنترلر تأمین‌کنندهٔ AXI DMA اعتبارسنجی نشده است.
3. **درایور DMA — تخصیص و خطا:** تخصیص/mmap/free هر بافر با device همان کانال DMA انجام می‌شود، cookie تکمیل بررسی می‌شود و طول TX/RX باید مضرب ۱۶/۴ بایت باشد. اگر terminate شکست بخورد، pending بی‌صدا پاک نمی‌شود. شکست terminate هنگام close/remove دستگاه را با نگه‌داشتن منابع و مرجع ماژول قرنطینه می‌کند؛ در آن مسیر خطای سخت‌افزار، reboot لازم است.
4. **Conv تولیدی:** وابستگی حلقوی START↔READY در handshake حذف شد. lint قبلی UNOPTFLAT داشت؛ پس از اصلاح این هشدار در top تولیدی وجود ندارد. این اصلاح ساختاری است؛ هشدار lint به‌تنهایی اثبات خرابی عددی یا نوسان سخت‌افزار قبلی نیست.
5. **Conv حافظه‌ای پژوهشی:** انتظار READY قبل از اولین START باعث توقف می‌شد. شروع نمونهٔ اول اصلاح شد؛ یک خروجی در حال پردازش نیز تا مصرف خروجی قبلی ظرفیت را رزرو می‌کند. دو تست جدید، حالت تک‌نمونه و چندنمونه را با توقف طولانی خروجی بررسی می‌کنند. این ماژول هنوز مسیر تولیدیِ داخل BD نیست.
6. **ONNX:** MaxPool بدون ویژگی strides طبق ONNX stride=1 دارد؛ مبدل قبلی به اشتباه آن را stride=2 می‌گرفت. اکنون این حالتِ پشتیبانی‌نشده را رد می‌کند. هشت تست واقعی parser/shape-inference/export/packer اضافه شد. این تست‌ها، اجرای عددی کامل گراف ONNX روی برد را اثبات نمی‌کنند.
7. **طراحی بلوکی DMA:** `c_sg_length_width=23` به‌صراحت تنظیم شد تا درخواست‌های تا 4 MiB نرم‌افزار از رجیستر طول سخت‌افزار بزرگ‌تر نباشند. پیش‌فرض مستند AXI DMA برابر 14 بیت است. این تغییر به بیلد تازه و device tree مطابق سخت‌افزار تازه نیاز دارد.
8. **Reset و IRQ:** قطبیت reset ورودی PS صریحاً active-low تنظیم شد؛ شکست اتصال وقفه‌های DMA/NPU اکنون build را متوقف می‌کند. این کار به معنی اثبات اشتباه بودن قطبیت نهایی بیلد قبلی نیست؛ پیکربندی تولیدشدهٔ آن اینجا موجود نیست.

## شواهد اجرا

| آزمون | نتیجه و محدوده |
|---|---|
| Icarus RTL | **55/55 PASS**؛ سه تست تازه نسبت به نسخهٔ 52تستی: AXI-Lite با 300 تراکنش و stall، Conv memory C1 و C2 |
| Add exhaustive | **131072 مقایسه PASS**؛ تمام جفت‌های INT8، با/بدون ReLU و backpressure |
| Verilator 5.020 | هر 29 ماژول یک‌بار به‌عنوان top بررسی شد؛ exit=0؛ بدون LATCH/MULTIDRIVEN/UNOPTFLAT در این اجرا. هشدارهای عرض/سیگنال استفاده‌نشده/پین‌های legacy باقی‌اند؛ ادعای lint کاملاً بدون هشدار مطرح نیست. |
| DMA concurrency/lifetime host mocks | پنج گروه تست PASS با کد واقعی توابع درایور، pthread، AddressSanitizer و UBSan؛ LeakSanitizer به دلیل محدودیت محیط غیرفعال بود. این تست، اجرای درون کرنل نیست. |
| خطای قابل بازتولید نسخهٔ قبل | دو WAIT: اول موفق، دومی timeout؛ نسخهٔ اصلاحی دومی را EINVAL می‌کند. لاگ قبل/بعد موجود است. |
| Kernel module | کامپایل و modpost/link واقعی مقابل هدرهای **Linux 6.8.0-31 x86-64**، با W=1؛ بدون warning سورس. پیام تفاوت نسخهٔ فرعی GCC و نبود vmlinux/BTF ثبت شده است. ARM/PetaLinux هدف هنوز تست نشده. باینری x86 ماژول داخل بسته تحویل نمی‌شود. |
| ONNX 1.23.2 | **8/8 PASS**؛ یک تست MaxPool قبل از اصلاح شکست می‌خورد. NumPy 2.5.4. وابستگی‌ها به‌صورت محلی برای تست تهیه شدند و در ZIP نیستند. |
| C server socketpair | 11 درخواست INFO/نامعتبر، طول‌ها و مرز Conv با 131071/131072 MAC، با ASan/UBSan: PASS |
| Tcl با mock API | تنظیم طول 23 بیت، reset active-low و خطای اجباری IRQ: PASS. **این، اجرای Vivado نیست.** |
| Static release gates | baseline 25/25، final 36/36، second 30/30، third 30/30؛ Python/C userspace و 11 تست نرم‌افزاری قبلی PASS |
| Bare-metal | تست mock قبلی DMA completion/failure/timeout PASS؛ کامپایل BSP واقعی هنوز لازم است. |
| Board selftest | فقط dry-run ساخت بسته‌ها PASS؛ نتیجهٔ Ethernet واقعی نداریم. |

`verification/evidence/deep_*.log`، `deep_all_module_lint.json` و `iverilog_results.json` شواهد این نسخه‌اند. لاگ‌های با نام review20 یا نام‌های قدیمی، تاریخی‌اند. گزارش‌های قدیمی به‌جای این گزارش ملاک تأیید نسخه نیستند.

## دامنهٔ ۲۵ بررسی

این‌ها ۲۵ موضوع بررسی‌اند، نه ۲۵ گواهی مستقل برای کل پروژه:

| # | موضوع | مدرک اصلی |
|---|---|---|
| 1 | فهرست سورس و hierarchy | inventory و lint تمام ماژول‌ها |
| 2 | عرض‌ها و signed arithmetic | lint و تست عددی RTL |
| 3 | MAC و skew/flush | تست‌های systolic و controller |
| 4 | tiling و مرز feed | regressions پیوستهٔ چند tile |
| 5 | bias و edge tile | regressions bias/mask |
| 6 | postprocess pipeline | equivalence و signed extremes |
| 7 | ترتیب خروجی و backpressure | تست multi-tile و DONE-after-stream |
| 8 | AW/W مستقل AXI-Lite | 300 تراکنش تازه |
| 9 | B/R با توقف مصرف‌کننده | همان تست تصادفی و تست‌های قبلی |
| 10 | WSTRB و قفل پیکربندی | تست‌های رجیستر |
| 11 | IRQ/abort/counters | تست‌های RTL رجیستر/سیستم |
| 12 | Conv تولیدی و config latch | regressions Conv |
| 13 | Conv آخرین نمونه و restart | final-fence regression |
| 14 | حلقهٔ START/READY | lint قبل/بعد و regression |
| 15 | Conv حافظه‌ای پژوهشی | دو تست تازه و رفع توقف |
| 16 | Add و saturation | تست exhaustive |
| 17 | MaxPool و علامت | تست RTL و بررسی semantics ONNX |
| 18 | ورودی‌های packer و SNPU | 11 تست نرم‌افزاری قبلی و ممیزی‌ها |
| 19 | مبدل واقعی ONNX | 8 تست تازه |
| 20 | پروتکل C/TCP و مرز طول‌ها | socketpair و تست کلاینت |
| 21 | رقابت ioctlهای DMA | تست pthread قبل/بعد |
| 22 | remove/close/mapping و خطای terminate | kref و تست قرنطینه |
| 23 | سازگاری کامپایل درایور | kernel module build واقعی |
| 24 | BD/reset/IRQ و ظرفیت DMA | منابع AMD و اجرای Tcl mock |
| 25 | بسته‌بندی و رگرسیون نهایی | hashes، ZIP CRC، لاگ‌های اجرای نهایی |

## بازتولید

```bash
bash scripts/validate_release.sh
python3 verification/run_iverilog.py
python3 verification/review20/run_exhaustive.py
python3 verification/deep/run_checks.py --onnx
```

Icarus برای شبیه‌سازی، gcc برای تست C، tclsh برای تست Tcl و onnx/numpy برای بخش اختیاری ONNX لازم‌اند. برای اجرای host checks بدون ONNX، `--onnx` را حذف کن؛ آن بخش صریحاً SKIP گزارش می‌شود. مسیرهای اختیاری: `IVERILOG`, `VVP`, `IVERILOG_BASE`, `TCLSH` و `KDIR`.

## آنچه هنوز تأیید نشده

- timing/DRC/utilization پس از route این نسخه؛ نتیجهٔ بیلد قبلی مربوط به همان سورس قبلی است.
- تأخیرهای I/O واقعی MII، هشدارهای PS7/MIO، revision و speed grade دقیق برد.
- بوت SD، لینوکس ARM، device tree هماهنگ با DMA تازه، Ethernet، انتقال DDR و inference روی برد.
- اجرای عمومی همهٔ مدل‌های ONNX؛ SNPU فعلی بستهٔ محدود وزن/لایه است و runtime کامل گراف و scheduler عمومی مدل ندارد.
- تست formal و اثبات بی‌باگ‌بودن تمام RTL و نرم‌افزار انجام نشده است. ماژول‌های قدیمی مثل npu_v4_top معادل top تولیدی و قابلیت‌های آن نیستند؛ build تولیدی از npu_bd_top استفاده می‌کند.

## منابع اصلی بررسی‌شده

- [Linux DMAengine client API](https://docs.kernel.org/driver-api/dmaengine/client.html): ترتیب submit/issue، cookie، callback و terminate/synchronize.
- [Linux kref rules](https://docs.kernel.org/core-api/kref.html): نگه‌داشتن مرجع پیش از انتشار pointer و آزادسازی در آخرین put.
- [Linux DMA mapping implementation](https://github.com/torvalds/linux/blob/master/kernel/dma/mapping.c): بافر coherent تا پایان mapping نباید آزاد شود.
- [Linux misc.c](https://github.com/torvalds/linux/blob/master/drivers/char/misc.c): هماهنگی misc_open با deregistration.
- [AMD AXI DMA PG021 v7.1](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/axi_dma/v7_1/pg021_axi_dma.pdf): پیش‌فرض 14 بیت برای رجیستر طول.
- [Xilinx PYNQ-DL DMA Tcl](https://github.com/Xilinx/PYNQ-DL/blob/master/resize/overlays/resize.tcl): نمونهٔ واقعی simple DMA با طول 23 بیت.
- [AMD UG925](https://docs.amd.com/api/khub/documents/5rGV8gWO5aZQvu~r9o0dVg/content): قطبیت active-low برای FCLK_RESET0_N.
- [ONNX MaxPool](https://onnx.ai/onnx/operators/onnx__MaxPool.html): stride پیش‌فرض 1، نه 2.
- [ONNX Conv](https://onnx.ai/onnx/operators/onnx__Conv.html): مرز قابلیت‌های exporter؛ این مراجعه، اجرای مدل روی سخت‌افزار نیست.

هیچ RTL شخص ثالثی در این اصلاحات کپی یا جایگزین نشده است. منابع برای بررسی قراردادها استفاده شده‌اند.
