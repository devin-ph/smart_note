# Smart Note

Ứng dụng ghi chú viết bằng Flutter - Bộ môn PTƯDDĐ.

## Thông tin sinh viên

- Họ tên: Phạm Hoàng Thế Vinh
- MSSV: 2351060498

## Cấu trúc mã nguồn chính

- `lib/main.dart`: Home screen, tìm kiếm, danh sách ghi chú, xóa ghi chú, điều hướng.
- `lib/note.dart`: Model `Note`, `toJson/fromJson`, encode/decode danh sách.
- `lib/note_storage.dart`: Đọc/ghi `SharedPreferences`.
- `lib/note_edit_screen.dart`: Màn hình tạo/sửa và auto-save khi Back.

## Cách chạy dự án

0. Clone dự án:

    ```bash
    git clone https://github.com/devin-ph/smart_note.git
    ```
1. Cài dependencies:

	```bash
	flutter pub get
	```

2. Chạy ứng dụng:

	```bash
	flutter run
	```

3. Kiểm tra phân tích:

	```bash
	flutter analyze
	```