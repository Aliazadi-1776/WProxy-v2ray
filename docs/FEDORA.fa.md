# اگر WProxy روی فدورا وصل نشد

این راهنما برای **Fedora Workstation و Fedora KDE معمولی با DNF** است. برای
Silverblue، Kinoite و سایر نسخه‌های Atomic، نصب سیستمی با این روش تأیید نشده است.
وابستگی‌ها و نصب اولیه در [README فارسی](../README.fa.md#نصب-لینوکس) آمده‌اند.

اصلاح اتصال روی یک لپ‌تاپ با NetworkManager 1.58.1 آزمایش شده است؛ این نتیجه
به‌معنی تست اتصال روی فدورا با SELinux Enforcing نیست. برای وضعیت دقیق به
[گزارش تست نصب‌شده](verification/2026-11-04-linux-connection.md) مراجعه کن.

## ۱. اول نسخه و موتور را بررسی کن

از حساب عادی دسکتاپ، نه یک نشست root:

```bash
/usr/bin/wproxyctl --version
/usr/libexec/wproxy-service --version
/usr/bin/wproxyctl core list --json
/usr/bin/wproxyctl status --json
systemctl is-active NetworkManager
```

نسخهٔ CLI و سرویس باید یکسان باشد و موتور کانفیگ در فهرست Coreها `available: true`
داشته باشد. نبودن `/run/NetworkManager/wproxy/xray.log` پیش از اولین اجرای موفق
به‌تنهایی به معنی نبودن Xray نیست. مسیر `/run/wproxy` متعلق به نسخه‌های قدیمی است.

اگر نسخه‌ها متفاوت‌اند یا فایل‌ها ناقص‌اند، از پوشهٔ سورس جدید و با وابستگی‌های
نصب‌شده دوباره نصب کن. نصب‌کننده از فایل‌های قبلی پشتیبان می‌گیرد:

```bash
# در همین مخزن؛ تغییرات محلی را با reset یا حذف فایل‌ها از بین نبر
git pull --ff-only

# Fedora KDE
bash scripts/install.sh --desktop kde

# روی GNOME به‌جای دستور بالا این را اجرا کن:
# bash scripts/install.sh --desktop gnome
```

برای نصب از ZIP، از پوشهٔ نسخهٔ جدید دستور نصب را اجرا کن؛ `git pull` لازم نیست.
کل برنامه را با `sudo wproxy-manager` اجرا نکن. درخواست دسترسی باید توسط خود
برنامه و فقط برای عملیات مجاز WProxy نمایش داده شود.

## ۲. سرور خراب را از مشکل برنامه جدا کن

```bash
/usr/bin/wproxyctl node list --json
# NODE_ID را از خروجی بالا جایگزین کن؛ لینک خصوصی کانفیگ لازم نیست
/usr/bin/wproxyctl node verify NODE_ID --timeout 8
```

این دستور Core را با یک پروکسی محلی برای HTTPS امتحان می‌کند و مسیر کل سیستم را
عوض نمی‌کند. اگر چند سرور مختلف این مرحله را رد می‌کنند، خطای Core/کانفیگ/شبکه
را بررسی کن. پاسخ‌دادن به TCP ping فقط بازبودن یک پورت را نشان می‌دهد؛ کارکرد
YouTube یا بقیهٔ سایت‌ها را ثابت نمی‌کند.

در Manager، حالت Routing را هم ببین:

- **All traffic**: ترافیک عادی لپ‌تاپ از VPN می‌رود.
- **Only selected**: فقط برنامه‌ها و سایت‌های انتخاب‌شده از VPN می‌روند.
- **Bypass selected**: موارد انتخاب‌شده مستقیم می‌مانند؛ بقیه از VPN می‌روند.

اگر برای حفظ ارتباط پشتیبانی، ChatGPT/Codex را bypass می‌کنی، مرورگر داخل همان
برنامه نیز ممکن است مستقیم برود. اتصال VPN را با مرورگر جداگانه و برنامه‌ای که
در bypass نیست امتحان کن. مسیر واقعی فایل اجرایی را از **Choose application**
انتخاب کن؛ یک launcher ممکن است با برنامهٔ در حال اجرا مسیر متفاوتی داشته باشد.

## ۳. `Unknown reason` یا قطع‌شدن بعد از مدتی

یک بار تلاش ناموفق انجام بده و بلافاصله این خروجی‌ها را محلی ببین:

```bash
/usr/bin/wproxyctl status --json
sudo journalctl -b -u NetworkManager --since '10 minutes ago' --no-pager -o cat
sudo journalctl -b _COMM=wproxy-service -n 80 --no-pager -o cat
sudo tail -n 80 /run/NetworkManager/wproxy/xray.log
systemctl show NetworkManager -p MainPID -p NRestarts
```

نبودن خروجی در یک لاگ به معنی نبودن مشکل نیست؛ ژورنال NetworkManager و AVCها را
هم بررسی کن. اگر `nm-settings-utils.c:103`، `status=6/ABRT` یا
`Message recipient disconnected from message bus without replying` دیدی،
ممکن است خود NetworkManager هنگام ذخیرهٔ پروفایل crash کرده باشد. نسخهٔ اصلاح‌شده
پس از load/reload دیگر `nmcli connection modify` اجرا نمی‌کند و Routing تازه را
از فایل root-owned خودش می‌خواند. نصب کامل نسخهٔ جدید را انجام بده؛ پروفایل‌ها را
برای رفع این خطا دستی و پی‌درپی modify نکن.

برای پاک‌کردن یک اجرای گیرکرده، فقط WProxy را متوقف و پروفایل‌هایش را sync کن:

```bash
/usr/bin/wproxyctl nm down
sudo /usr/libexec/wproxy-xray-runner stop
sudo /usr/bin/wproxyctl nm sync
```

سپس از Manager دوباره وصل شو. restart کل NetworkManager می‌تواند Wi-Fi و سایر
اتصال‌ها را قطع کند و جزو مراحل معمول این راهنما نیست. اگر NetworkManager اصلاً
فعال نیست، ابتدا همان سرویس و اتصال پایهٔ Wi-Fi/Ethernet را بررسی کن.

## ۴. بررسی SELinux بدون خاموش‌کردنش

```bash
getenforce
sudo ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts recent -i

# این پوشه معمولاً پس از تلاش برای اتصال ساخته می‌شود
sudo ls -Zd /run/NetworkManager /run/NetworkManager/wproxy
sudo matchpathcon -V /run/NetworkManager/wproxy
```

اگر ابزارها نصب نیستند، روی فدورای معمولی `sudo dnf install audit policycoreutils`
آن‌ها را فراهم می‌کند. مقدار مورد انتظار label را از policy همان سیستم با
`matchpathcon` بگیر. در گزارش‌های قبلی، runtime با `tmp_t` یا `var_run_t` باعث
denial شده بود؛ مسیر فعلی زیر پوشهٔ خود NetworkManager قرار دارد.

اگر label اشتباه است، فقط مسیرهای WProxy را به مقدار پیش‌فرض policy برگردان:

```bash
if [ -d /run/NetworkManager/wproxy ]; then
    sudo restorecon -Rv /run/NetworkManager/wproxy
fi
sudo restorecon -v /usr/libexec/wproxy-service /usr/libexec/wproxy-xray-runner /usr/bin/wproxyctl
```

دوباره وصل شو و AVC تازه را بررسی کن. اگر هنوز denial وجود دارد، type مبدأ، type
مقصد، عملیات denied و مسیر مربوط به WProxy را در گزارش بفرست. از `setenforce 0`،
`chmod 777` یا ساخت خودکار policy با `audit2allow` به‌عنوان راه‌حل عمومی استفاده
نکن؛ مشکل label با اضافه‌کردن مجوزهای گسترده حل نمی‌شود.

مرجع دستورات: [راهنمای عیب‌یابی SELinux فدورا](https://fedoraproject.org/wiki/SELinux/Troubleshooting)
و [مدیریت file context در فدورا](https://fedoraproject.org/wiki/SELinux/ManagingFileContext).

## ۵. اگر KDE می‌گوید پشتیبانی VPN نوع wproxy وجود ندارد

این خطا می‌تواند از نبودن افزونهٔ بومی Plasma باشد، حتی اگر Manager نصب باشد.
وابستگی‌های KDE را طبق README نصب و نصب‌کننده را با `--desktop kde` اجرا کن.
راهنمای [KDE](KDE.md) را هم ببین. بعد از نصب افزونه، یک بار خارج و وارد نشست شو؛
ری‌استارت NetworkManager برای بارگذاری رابط Plasma لازم نیست.

اگر پیام `Command timed out` می‌بینی، نتیجهٔ همان عمل را در Manager و
`wproxyctl status --json` بررسی کن و ژورنال را بگیر؛ timeout رابط را معادل سالم یا
خراب بودن تونل حساب نکن.

## ۶. اگر مرتب دسترسی مدیر می‌خواهد

در Settings گزینهٔ **Ask for permission only once** را روشن و اولین درخواست
Polkit را تأیید کن. این گزینه مجوز عملیات محدود WProxy را برای حساب محلی و نشست
فعال به خاطر می‌سپارد؛ رمز sudo ذخیره نمی‌شود. برای لغو، همان گزینه را خاموش کن.

اگر پنجرهٔ اجازه اصلاً باز نمی‌شود، از نشست کامل KDE/GNOME با agent احراز هویت
Polkit استفاده کن و وضعیت `systemctl status polkit --no-pager` را بررسی کن.
انقضای timestamp مربوط به sudo به‌تنهایی نباید Core فعال NetworkManager را متوقف
کند؛ برای قطع بعد از ده دقیقه، لاگ همان لحظه لازم است. قاعدهٔ عمومی NOPASSWD
برای همهٔ دستورها اضافه نکن.

## ۷. بعد از اتصال، اینترنت واقعی را امتحان کن

برنامهٔ تست باید طبق Routing از VPN عبور کند. از حساب عادی دسکتاپ:

```bash
curl --noproxy '*' --location --fail --silent --show-error \
  --connect-timeout 8 --max-time 25 --output /dev/null \
  --write-out 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}s\n' \
  https://www.youtube.com/
ping -c 4 -W 2 www.youtube.com
```

برای این درخواست، خروجی HTTP موفق و دریافت کامل صفحه مهم‌اند. ping به‌تنهایی
پخش ویدئو را تأیید نمی‌کند؛ video playback را در مرورگر جدا امتحان کن.

تست خودکار اتصال و Switch روی **نسخهٔ نصب‌شده** نیز وجود دارد؛ قبل از اجرا اتصال
فعلی WProxy را قطع کن. این تست موقتاً All traffic را فعال می‌کند و در پایان به
حالت قبلی برمی‌گردد؛ ممکن است ارتباط راه‌دور را مختل کند:

```bash
python3 scripts/live-installed-smoke.py --confirm --quick --temporary-all
# برای تست Switch، NODE_A و NODE_B را با دو شناسهٔ ذخیره‌شده جایگزین کن
python3 scripts/live-installed-smoke.py --confirm --node NODE_A --switch-node NODE_B --temporary-all
```

## چه چیزی در Issue بفرستم؟

نسخهٔ فدورا، KDE/GNOME، روش نصب، نسخهٔ CLI و سرویس، inventory موتورها، حالت
Routing، نتیجهٔ HTTPS و بخش مرتبط ژورنال/AVC را بفرست. مسیر فایل اجرایی برنامهٔ
انتخاب‌شده در Routing نیز کمک می‌کند.

فایل‌های `~/.config/wproxy/store.json`، فایل‌های `.nmconnection`، کانفیگ Core،
لینک ساب/کانفیگ، UUID کاربری سرور، رمزها و IPهای شخصی را منتشر نکن. خروجی
`bash scripts/diagnose.sh` و لاگ‌های خام را قبل از ارسال بازبینی و پاک‌سازی کن.
