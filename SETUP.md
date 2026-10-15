# Hướng dẫn setup ztms trên máy mới

Có 2 cách:

- **Cách A: chuyển từ máy cũ** (nên dùng). Mang theo toàn bộ config, `tms.env.local` và các password.
- **Cách B: setup từ đầu.** Dùng khi không có máy cũ để export.

Dù theo cách nào, cuối cùng đều chạy **SETUP > doctor** để kiểm tra còn thiếu gì.

---

## 0. Cài sẵn trên máy mới

Bắt buộc:

| Công cụ | Cài bằng |
|---|---|
| git | `winget install Git.Git` |
| PowerShell 7+ (`pwsh`) | `winget install Microsoft.PowerShell` |

Cài thêm tuỳ tính năng bạn dùng (doctor sẽ báo cái nào thiếu):

| Công cụ | Cần cho |
|---|---|
| .NET SDK (`dotnet`) | BACKEND run/publish |
| Docker Desktop | Postgres/Redis local |
| PostgreSQL client (`psql`, `pg_dump`, `pg_restore`) | DATABASE clone/restore. Thêm thư mục `bin` của Postgres vào PATH |
| Node.js + yarn | FRONTEND |
| Android SDK (emulator) | ANDROID |
| VS Code (`code`) | open-vscode |
| Node.js >= 20 | HTTPTOOLKIT. Lệnh `htk` do **HTTPTOOLKIT > install** tự cài, không cần cài riêng |

> **Tên user Windows có dấu** (vd. `TrầnCôngMinh`): một số installer (Visual Studio Installer, ...) lỗi khi giải nén vào `%TEMP%`. Nếu gặp lỗi lạ kiểu "failed to download", đổi biến `TEMP`/`TMP` của user sang một thư mục không dấu, vd. `D:\Temp`.

---

## Cách A: chuyển từ máy cũ

### A1. Trên máy cũ: export

```powershell
ztms
# chọn SETUP > export
```

- Đặt passphrase (tối thiểu 8 ký tự, phải nhớ để import).
- Kết quả là file `ztms-backup-<ngày>.ztmsbak`, mặc định ngoài Desktop. File chứa:
  - `tms.config.json`
  - `tms.env.local`
  - giá trị của mọi biến môi trường ztms dùng (password DB/Redis/PMS, các key runtime)

> ⚠️ File này chứa **password**. Chỉ chép qua USB hoặc thư mục share riêng. **Không** gửi qua chat/email, **không** commit lên git. Import xong thì xoá.

### A2. Trên máy mới: cài ztms

```powershell
irm https://raw.githubusercontent.com/minhtrn98/ztms/master/install.ps1 | iex
```

Mở **terminal mới** rồi gõ `ztms`.

### A3. Import

```powershell
ztms
# chọn SETUP > import → nhập đường dẫn file .ztmsbak và passphrase
```

Import sẽ:
1. Hỏi lại các **đường dẫn riêng của máy**: `reposRoot`, `deployRoot`, thư mục emulator Android, thư mục repo HTTP Toolkit, thư mục PMS. Bấm Enter để giữ giá trị cũ.
2. Ghi `tms.config.json` và `tms.env.local`. Nếu đã có file cũ thì lưu lại thành `*.bak`.
3. Đặt các biến môi trường ở mức user.
4. Tự chạy **doctor**.

Sau đó **mở terminal mới** để nhận biến môi trường, rồi xoá file `.ztmsbak`.

### A4. Clone các repo service

Nếu doctor báo `service repos ... not cloned yet`, clone các repo đó vào `reposRoot` rồi chạy **COMMON > pull-all**.

### A5. HTTP Toolkit (nếu dùng)

Nhóm **HTTPTOOLKIT** chỉ hiện khi đã cấu hình `httptoolkit.repoPath` (qua import hoặc init-config).

```powershell
ztms
# chọn HTTPTOOLKIT > install
```

Lệnh này:
1. Clone `httptoolkit.gitUrl` vào `httptoolkit.repoPath` nếu thư mục đó chưa có. Nếu đã clone sẵn thì dùng luôn.
2. `git fetch`, rồi checkout branch `httptoolkit.branch` (mặc định `window-minh`), hoặc `pull --ff-only` nếu đang ở branch đó.
   - Repo có thay đổi chưa commit thì **không** đổi branch, chỉ báo lỗi. Code của bạn không bị mất.
3. Thêm `<repo>\scripts` vào PATH của user. Mở terminal mới là gõ `htk` được ở bất kỳ đâu.
4. Chạy `htk build`: `npm install` (lần đầu), build UI, deploy sang `D:\Deployments\custom-http-toolkit` (đổi được qua `httptoolkit.deployDir`), rồi start ở http://localhost:8080.

Cần **Node.js >= 20**. Chạy lại `install` bất cứ lúc nào để cập nhật. Sau khi tự sửa code thì dùng **HTTPTOOLKIT > build**.

### A6. PMS (nếu dùng)

```powershell
ztms
# chọn PMS > [dev] install
```

Lệnh này tải bản PMS mới nhất, tạo shortcut **PMS Dev** ngoài Desktop (luôn mở bản mới nhất, tự copy password vào clipboard) và tạo scheduled task **PMS Dev Auto Update** (check bản mới mỗi phút, báo bằng thông báo Windows).

> Nếu máy mới chưa từng cài PMS, nên chạy installer chính thức (`PMSSetup.exe`) một lần để có thư mục `Microsoft.WebView2.FixedVersionRuntime.*`. `[dev] install` sẽ cảnh báo nếu thiếu thư mục này.

---

## Cách B: setup từ đầu

1. Cài ztms như bước **A2**.
2. **SETUP > init-config**: trả lời các câu hỏi (thư mục repo, service/port, DB, Redis, frontend, Android, HTTP Toolkit, PMS) để tạo `tms.config.json`.
   - Phần stg (`stgHost`, ...) và `android.deploy` thì init-config chưa hỏi. Thêm tay theo `tms.config.example.json` nếu cần.
3. Tạo `tms.env.local`:
   ```powershell
   copy tms.env.example tms.env.local
   # điền giá trị thật vào tms.env.local
   ```
   Rồi chạy **SETUP > set-env** và chọn **persist** để lưu ở mức user.
4. Đặt các password (hoặc bỏ qua, script sẽ hỏi khi cần):
   ```powershell
   [Environment]::SetEnvironmentVariable('DEV_DB_PASSWORD', '<password>', 'User')
   ```
   Danh sách biến xem ở bảng bên dưới.
5. **SETUP > doctor** để kiểm tra, rồi làm tiếp **A4**, **A5** và **A6**.

> Menu **init-config** / **set-env** có thể bị ẩn bởi `hiddenMenuItems` trong `tms.config.json`. Nếu không thấy thì chạy trực tiếp: `.\setup\init-config.ps1`, `.\setup\set-env.ps1`.

---

## Các biến môi trường ztms dùng

Danh sách đầy đủ và trạng thái trên máy: chạy **SETUP > doctor**. Danh sách này được đọc từ config, nên luôn khớp với config hiện tại.

**Password** (tên biến khai báo trong `tms.config.json`):

| Biến | Dùng cho | Nếu chưa đặt |
|---|---|---|
| `TMS_LOCAL_DB_PASSWORD` | Postgres local | mặc định `postgres` |
| `DEV_DB_PASSWORD` / `STG_DB_PASSWORD` | clone DB dev / stg | script hỏi khi chạy |
| `DEV_REDIS_PW` / `STG_REDIS_PW` | clone Redis dev / stg | script hỏi khi chạy |
| `PMS_DEV_PASSWORD` | PMS > [dev] start copy vào clipboard | không copy |

**Runtime cho service .NET**: mọi key trong `tms.env.local` (`DefaultKey`, `Identity__Key`, `Redis__*`, `KafkaFlow__*`, `RabbitMq__*`, `OpenTelemetry__*`, ...). Sửa file xong thì chạy lại **SETUP > set-env** và chọn persist.

> Thêm password mới: khai báo thành một key `*PasswordEnvVar` trong config (hoặc một key trong `tms.env.local`). Doctor, export và import sẽ tự biết, không cần sửa code.

---

## Đọc kết quả doctor

| Trạng thái | Ý nghĩa |
|---|---|
| `OK` | ổn |
| `WARN` | thiếu nhưng không chặn. Chỉ ảnh hưởng tính năng liên quan, hoặc script sẽ hỏi khi cần |
| `FAIL` | phải sửa: thiếu `tms.config.json`, thiếu `git`, hoặc `reposRoot` không tồn tại |

Các WARN hay gặp:

- `in tms.env.local but not persisted` / `user-level value differs from tms.env.local`: chạy **SETUP > set-env**, chọn persist.
- `not on PATH`: cài công cụ đó, hoặc thêm vào PATH rồi mở terminal mới.
- `htk ... run HTTPTOOLKIT > install`: chạy **HTTPTOOLKIT > install**.
- `PMS ... run PMS > [dev] install`: chạy **PMS > [dev] install**.

---

## Gỡ cài đặt

```powershell
Remove-Item "$env:LocalAppData\Microsoft\WindowsApps\ztms.cmd"   # bỏ lệnh ztms
Unregister-ScheduledTask 'PMS Dev Auto Update' -Confirm:$false     # nếu đã cài PMS
```

Rồi xoá thư mục repo. Lưu ý `tms.config.json` và `tms.env.local` nằm trong đó và không có trên git. Muốn giữ lại thì **export trước**.
