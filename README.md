<p align="center">
  <img src="Assets/AppIcon.png" alt="SuperTrans App Icon" width="128" height="128" />
</p>

<h1 align="center">SuperTrans</h1>

<p align="center">
  <strong>Ultra-Lightweight Native macOS Personal AI Translator Powered by Gemini AI</strong><br>
  <em>Swift &bull; SwiftUI &bull; Cursor Popup &bull; Multi-Key Rotation &bull; Text &amp; Image Vision &bull; Auto-Update &bull; Universal 2</em>
</p>

<p align="center">
  <a href="#tiếng-việt">Tiếng Việt</a> &bull; <a href="#english">English</a>
</p>

<p align="center">
  <a href="https://github.com/nhanqv-ai/SuperTrans/releases"><img src="https://img.shields.io/github/v/release/nhanqv-ai/SuperTrans?style=flat-square&color=blue" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Sonoma%20%7C%20Sequoia-lightgrey.svg?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/architecture-Universal%202%20(arm64%20%2B%20x86__64)-blue.svg?style=flat-square" alt="Architecture">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square" alt="Swift">
</p>

---

<a name="tiếng-việt"></a>
## Tiếng Việt

**SuperTrans** (`com.nhanqv.supertrans`) là ứng dụng trợ lý dịch cá nhân siêu nhẹ, native cho macOS (hỗ trợ gốc cả chip Apple Silicon `arm64` và Intel `x86_64`), sử dụng **Google Gemini AI** để dịch văn bản và hình ảnh tức thì ngay phía trên con trỏ chuột và quản lý lịch sử dịch trên thanh Menu Bar tương tự [SuperClip](https://github.com/nhanqv-ai/SuperClip).

### Tính năng nổi bật

- **3 chế độ kích hoạt dịch linh hoạt**:
  1. **Phím tắt dịch nhanh (`Option + T`)**: Tự động lấy văn bản đang bôi đen trên màn hình (hoặc lấy văn bản/hình ảnh trong clipboard) và bật **Popup dịch ngay phía trên con trỏ chuột**.
  2. **Nhấn đúp Copy (`Cmd + C + C`)**: Nhấn `Cmd + C` 2 lần liên tiếp (trong 0.45 giây) để dịch ngay nội dung vừa copy.
  3. **Tự động dịch mọi thao tác Copy (`Auto`)**: Có thể bật/tắt nhanh ngay trên thanh tiêu đề Menu Bar hoặc trong Cài đặt khi cần đọc tài liệu ngoại ngữ liên tục.
- **Popup dịch gọn gàng ngay phía trên Cursor**:
  - Tự động căn vị trí ngay phía trên con trỏ chuột (và tự động lật xuống dưới nếu con trỏ sát mép trên màn hình).
  - Hỗ trợ **Copy nhanh (`Enter`)**, **Ghim cửa sổ (`Pin`)**, **Đổi nhanh ngôn ngữ đích**, **Xem lại nội dung/ảnh gốc**, và **Dịch lại**.
- **Hỗ trợ cả Văn bản (Text) & Hình ảnh (Image Vision)**:
  - Khi chụp màn hình vào clipboard (`Cmd + Ctrl + Shift + 4`) hoặc copy ảnh, SuperTrans tự động gửi ảnh qua Gemini Multimodal Vision để trích xuất chữ (OCR) và dịch sang ngôn ngữ đích.
- **Xoay vòng nhiều Gemini API Key (Multi-Key Rotation) & Tối ưu tốc độ dịch (~0.7s)**:
  - Cho phép nhập danh sách nhiều API Key của Gemini.
  - Tự động xoay vòng luân phiên (Round-Robin) và tự động chuyển sang key tiếp theo ngay lập tức nếu một key gặp giới hạn hạn mức miễn phí (`HTTP 429 Resource Exhausted`).
  - Hỗ trợ Pulldown chọn nhanh các Model Gemini thế hệ mới tốc độ cao (`gemini-3.1-flash-lite` mặc định ~0.7s, `gemini-3.5-flash-lite`, `gemini-3-flash-preview`, `gemini-3.5-flash` hoặc tự nhập Model ID tuỳ chỉnh) và tùy chỉnh **System Prompt**.
- **Lịch sử dịch trên Menu Bar & Cửa sổ nổi (`Option + Shift + T`)**:
  - Giao diện 1 dòng gọn gàng tương tự SuperClip, tìm kiếm tức thì không phân biệt dấu tiếng Việt trên cả bản gốc và bản dịch.
  - **Rê chuột (Hover)** vào từng dòng để xem bảng Preview hiển thị đầy đủ cả **Nội dung gốc / Ảnh gốc** lẫn **Bản dịch**.
  - Chọn bằng chuột hoặc phím mũi tên `↑`/`↓` + `Enter` để Copy / Auto-Paste ngay bản dịch.
- **Tự động kiểm tra & Cập nhật ứng dụng 1 chạm (`UpdateManager`)**:
  - Tự động kiểm tra phiên bản mới từ GitHub Releases khi khởi động và định kỳ mỗi 24 giờ, hoặc kiểm tra thủ công trong **Cài đặt -> Thông tin** / Menu chuột phải trên Menu Bar.
  - Hỗ trợ tải ngầm, giải nén, xác thực chữ ký và khởi động lại phiên bản mới chỉ với 1 nút bấm **"Cập nhật ngay"**.

---

### Hướng dẫn tạo Gemini API Key miễn phí trên Google AI Studio

Để sử dụng SuperTrans, bạn chỉ cần tạo một (hoặc nhiều) **Gemini API Key** hoàn toàn miễn phí từ **Google AI Studio** theo các bước sau:

1. **Truy cập Google AI Studio**:
   - Mở trình duyệt và truy cập: **[https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)**
   - Đăng nhập bằng tài khoản Google (Gmail) của bạn.
2. **Tạo API Key mới**:
   - Nhấn vào nút **"Create API key"** (Tạo khóa API) ở góc trên bên phải.
   - Chọn **"Create API key in new project"** (Tạo khóa API trong dự án mới) hoặc chọn một Google Cloud Project có sẵn.
   - Đợi vài giây để Google khởi tạo key (có dạng bắt đầu bằng `AIzaSy...`), sau đó nhấn **"Copy"** để sao chép key vào Clipboard.
3. **(Mẹo khuyên dùng) Tạo nhiều API Key để xoay vòng vượt giới hạn Rate Limit**:
   - Gói miễn phí (Free Tier) của Gemini giới hạn số lượt gọi mỗi phút (RPM) trên từng Project.
   - Bạn có thể nhấn **"Create API key" -> "Create API key in new project"** thêm 2–3 lần nữa (hoặc tạo từ các tài khoản Google khác nhau) để lấy nhiều key.
4. **Dán API Key vào SuperTrans**:
   - Nhấn vào biểu tượng **SuperTrans** trên thanh Menu Bar -> chọn biểu tượng bánh răng **Cài đặt (`Cmd + ,`)** -> chuyển sang tab **Gemini AI**.
   - Nhấn trực tiếp nút **"Dán & Thêm"** (hoặc dán `Cmd + V` vào ô nhập rồi nhấn **Thêm Key**). Bạn có thể dán nhiều key cùng lúc (cách nhau bằng dấu phẩy hoặc xuống dòng).
   - Nhấn **"Kiểm tra tất cả Key"** để xác nhận trạng thái **Đang dùng tốt** (màu xanh lá).

---

### Phím tắt mặc định

| Phím tắt | Thao tác | Phạm vi |
| :--- | :--- | :--- |
| `Option + T` | Dịch vùng đang chọn / Clipboard và mở Popup phía trên chuột | Toàn hệ thống |
| `Cmd + C + C` | Nhấn `Cmd + C` 2 lần liên tiếp để dịch nhanh | Toàn hệ thống |
| `Option + Shift + T` | Mở cửa sổ nổi Lịch sử dịch tại vị trí chuột | Toàn hệ thống |
| `Enter` | Copy bản dịch và đóng Popup / chọn mục lịch sử | Trong Popup / Lịch sử |
| `Escape` | Đóng cửa sổ Popup / Lịch sử | Trong Popup / Lịch sử |
| `Command + ,` | Mở Cài đặt (Preferences) | Trong Popup / Lịch sử |

---

### Hướng dẫn cài đặt ứng dụng

1. Tải bản phát hành mới nhất tại mục **[Releases](https://github.com/nhanqv-ai/SuperTrans/releases/latest)** (`SuperTrans-v1.0.5.zip`).
2. Giải nén và kéo `SuperTrans.app` vào thư mục `/Applications`.
3. Mở `SuperTrans.app`, nhấn vào icon trên Menu Bar -> **Cài đặt... (`Cmd + ,`)** -> tab **Gemini AI** và nhấn **"Dán & Thêm"** để thêm Gemini API Key.

> [!NOTE]
> **Mở ứng dụng lần đầu (macOS Gatekeeper)**:
> Nếu macOS hiển thị thông báo bảo vệ khi mở lần đầu, hãy chạy lệnh sau trong Terminal:
> ```bash
> xattr -cr /Applications/SuperTrans.app
> ```
> Nếu cần làm mới quyền Trợ năng (Accessibility) sau khi cập nhật:
> ```bash
> tccutil reset Accessibility com.nhanqv.supertrans
> ```

### Biên dịch từ mã nguồn

```bash
git clone https://github.com/nhanqv-ai/SuperTrans.git
cd SuperTrans
make app
open SuperTrans.app
```

---

<a name="english"></a>
## English

**SuperTrans** (`com.nhanqv.supertrans`) is an ultra-lightweight, native macOS personal AI translation assistant built with Swift and SwiftUI. Powered by **Google Gemini AI**, it translates selected or copied text and images right above your mouse cursor and maintains a searchable translation history in the macOS menu bar.

### Highlights

- **3 Flexible Trigger Modes**:
  1. **Global Translate Shortcut (`Option + T`)**: Automatically grabs currently highlighted text (or falls back to current clipboard text/image) and presents the translation popup right above your mouse cursor.
  2. **Double Copy (`Cmd + C + C`)**: Press `Cmd + C` twice within 0.45s to immediately translate copied content.
  3. **Auto-Translate Every Copy (`Auto`)**: One-click toggle in the Menu Bar popover or Preferences for continuous foreign-language reading.
- **Clean Cursor Translation Popup**:
  - Appears directly above the mouse cursor (with automatic screen-boundary clamping).
  - Supports **Instant Copy (`Enter`)**, **Pin Popup**, **On-the-fly Target Language switching**, **Collapsible Original Content**, and **Re-translate**.
- **Text & Image Vision Support**:
  - Translates both plain text and copied screenshots/images using Gemini Multimodal Vision OCR.
- **Multi-API Key Rotation & Fast Gemini 3.x Models (~0.7s)**:
  - Add multiple Gemini API keys to automatically rotate and fail over seamlessly when hitting free-tier `HTTP 429` rate limits.
  - Pulldown selector for verified low-latency Gemini models (`gemini-3.1-flash-lite` default, `gemini-3.5-flash-lite`, `gemini-3-flash-preview`, `gemini-3.5-flash`, or custom model ID) and customizable **System Prompt**.
- **Menu Bar & Floating Translation History (`Option + Shift + T`)**:
  - Single-line compact layout inspired by [SuperClip](https://github.com/nhanqv-ai/SuperClip) with diacritic-insensitive instant search across both original and translated text.
  - **Dual Hover Preview**: Hovering over any history row displays both the **Original Content (Text/Image)** and the **Full Translation**.
- **Built-in Automatic & Manual Update Checker (`UpdateManager`)**:
  - Checks GitHub Releases on startup and every 24 hours, with 1-click background download, signature verification, and app restart.

### How to Get a Free Gemini API Key in Google AI Studio

1. Open **[Google AI Studio API Keys](https://aistudio.google.com/app/apikey)** and sign in with your Google account.
2. Click **"Create API key"** -> **"Create API key in new project"** and copy the generated key (`AIzaSy...`).
3. *(Optional)* Create 2–3 keys in different projects to maximize free-tier quota via SuperTrans's automatic key rotation.
4. In SuperTrans, open **Settings (`Cmd + ,`) -> Gemini AI** and click **"Paste & Add"** (`Dán & Thêm`).

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
