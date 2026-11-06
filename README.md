<p align="center">
  <img src="Assets/AppIcon.png" alt="SuperTrans App Icon" width="128" height="128" />
</p>

<h1 align="center">SuperTrans</h1>

<p align="center">
  <strong>Ultra-Lightweight Native macOS Personal AI Translator Powered by Gemini AI</strong><br>
  <em>Swift &bull; SwiftUI &bull; Cursor Popup &bull; Multi-Key Rotation &bull; Text &amp; Image Vision &bull; Universal 2</em>
</p>

<p align="center">
  <a href="#tiếng-việt">Tiếng Việt</a> &bull; <a href="#english">English</a>
</p>

<p align="center">
  <a href="https://github.com/nhanqv-ai/SuperTrans/releases"><img src="https://img.shields.io/github/v/release/nhanqv-ai/SuperTrans?style=flat-square&color=blue" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Sonoma%2014.6%2B-lightgrey.svg?style=flat-square" alt="Platform">
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
  2. **Nhấn đúp Copy (`Cmd + C + C`)**: Nhấn `Cmd + C` 2 lần liên tiếp (trong 0.4 giây) để dịch ngay nội dung vừa copy.
  3. **Tự động dịch mọi thao tác Copy (`Auto`)**: Có thể bật/tắt nhanh ngay trên thanh tiêu đề Menu Bar hoặc trong Cài đặt khi cần đọc tài liệu ngoại ngữ liên tục.
- **Popup dịch ngay phía trên Cursor**:
  - Tự động căn vị trí ngay phía trên con trỏ chuột (và tự động lật/chống tràn nếu sát mép trên màn hình).
  - Hỗ trợ **Copy nhanh (`Enter`)**, **Tự động dán đè (`Cmd + Enter`)** vào ứng dụng đang gõ, **Ghim cửa sổ (`Pin`)**, **Đổi nhanh ngôn ngữ đích**, **Xem lại nội dung/ảnh gốc**, và **Dịch lại**.
- **Hỗ trợ cả Văn bản (Text) & Hình ảnh (Image Vision)**:
  - Khi chụp màn hình vào clipboard (`Cmd + Ctrl + Shift + 4`) hoặc copy ảnh, SuperTrans tự động gửi ảnh qua Gemini Multimodal Vision để trích xuất chữ (OCR) và dịch sang ngôn ngữ đích.
- **Xoay vòng nhiều Gemini API Key (Multi-Key Rotation)**:
  - Cho phép nhập danh sách nhiều API Key của Gemini.
  - Tự động xoay vòng luân phiên và tự động chuyển sang key tiếp theo ngay lập tức nếu một key gặp lỗi giới hạn hạn mức miễn phí (`HTTP 429 Resource Exhausted`).
  - Hỗ trợ chọn nhanh Model (`gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-2.0-flash`, `gemini-2.5-pro` hoặc tự nhập tên model mới) và tùy chỉnh **System Prompt**.
- **Lịch sử dịch trên Menu Bar & Cửa sổ nổi (`Option + Shift + T`)**:
  - Giao diện 1 dòng gọn gàng tương tự SuperClip, tìm kiếm tức thì không phân biệt dấu tiếng Việt trên cả bản gốc và bản dịch.
  - **Rê chuột (Hover)** vào từng dòng để xem bảng Preview hiển thị đầy đủ cả **Nội dung gốc / Ảnh gốc** lẫn **Bản dịch**.
  - Chọn bằng chuột, `Enter`, hoặc phím số `1..9` để Copy / Auto-Paste ngay bản dịch.

### Phím tắt mặc định

| Phím tắt | Thao tác | Phạm vi |
| :--- | :--- | :--- |
| `Option + T` | Dịch vùng đang chọn / Clipboard và mở Popup phía trên chuột | Toàn hệ thống |
| `Cmd + C + C` | Nhấn `Cmd + C` 2 lần liên tiếp để dịch nhanh | Toàn hệ thống |
| `Option + Shift + T` | Mở cửa sổ nổi Lịch sử dịch tại vị trí chuột | Toàn hệ thống |
| `Enter` | Copy bản dịch và đóng Popup / chọn mục lịch sử | Trong Popup / Lịch sử |
| `Cmd + Enter` | Tự động dán (Auto-Paste) bản dịch vào ô đang gõ | Trong Popup |
| `1` .. `9` | Chọn và dán nhanh mục lịch sử từ 1 đến 9 | Trong Lịch sử |
| `Escape` | Đóng cửa sổ Popup / Lịch sử | Trong Popup / Lịch sử |
| `Command + ,` | Mở Cài đặt (Preferences) | Trong Popup / Lịch sử |

### Hướng dẫn cài đặt

1. Tải bản phát hành mới nhất `SuperTrans-v1.0.0.zip` tại mục [Releases](https://github.com/nhanqv-ai/SuperTrans/releases).
2. Giải nén và kéo `SuperTrans.app` vào thư mục `/Applications`.
3. Mở `SuperTrans.app`, nhấn vào icon trên Menu Bar -> **Cài đặt... (`Cmd + ,`)** -> tab **Gemini AI** để thêm Gemini API Key.

> [!NOTE]
> **Mở ứng dụng lần đầu (macOS Gatekeeper)**:
> Nếu macOS hiển thị thông báo bảo vệ khi mở lần đầu, hãy chạy lệnh sau trong Terminal:
> ```bash
> xattr -cr /Applications/SuperTrans.app
> ```
> Nếu cần làm mới quyền Trợ năng (Accessibility):
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
  2. **Double Copy (`Cmd + C + C`)**: Press `Cmd + C` twice within 0.4s to immediately translate copied content.
  3. **Auto-Translate Every Copy (`Auto`)**: One-click toggle in the Menu Bar popover or Preferences for continuous foreign-language reading.
- **Cursor Translation Popup**:
  - Appears directly above the mouse cursor (with automatic screen-boundary clamping).
  - Supports **Instant Copy (`Enter`)**, **Direct Auto-Paste / Replace (`Cmd + Enter`)**, **Pin Popup**, **On-the-fly Target Language switching**, **Collapsible Original Content**, and **Re-translate**.
- **Text & Image Vision Support**:
  - Translates both plain text and copied screenshots/images using Gemini Multimodal Vision OCR.
- **Multi-API Key Rotation**:
  - Add multiple Gemini API keys to automatically rotate and fail over seamlessly when hitting free-tier `HTTP 429` rate limits.
  - Configurable Gemini Model (`gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-2.0-flash`, `gemini-2.5-pro`, or custom model ID) and customizable **System Prompt**.
- **Menu Bar & Floating Translation History (`Option + Shift + T`)**:
  - Single-line compact layout inspired by [SuperClip](https://github.com/nhanqv-ai/SuperClip) with diacritic-insensitive instant search across both original and translated text.
  - **Dual Hover Preview**: Hovering over any history row displays both the **Original Content (Text/Image)** and the **Full Translation**.
  - Select with `Enter` or number keys `1..9` for instant Copy or Direct Auto-Paste.

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
