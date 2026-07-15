# Hướng dẫn kết nối — iOS ↔ TTBDebugPlus

Tài liệu ngắn gọn về cách kết nối app iOS với TTBDebugPlus trên Mac. Muốn xem hướng dẫn tích hợp đầy đủ (thêm SDK, gửi log...) thì xem [README.md](README.md). Trang này chỉ nói về **kết nối**.

## Tóm tắt nhanh

1. Thêm `TTBaseUIKit` vào app iOS (qua SPM).
2. Thêm 2 key vào Info.plist của app iOS (xem bên dưới).
3. Gọi `TTDebugBridge.shared.start()`.
4. Mở **TTBDebugPlus** trên Mac, cùng mạng Wi-Fi với iPhone. Xong — tự kết nối, không cần làm gì thêm.

## Cài đặt (làm 1 lần)

**Info.plist** — bắt buộc, thiếu thì SDK không bao giờ tìm được Mac:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Required for connecting to TTBDebugPlus on macOS to stream debug logs.</string>
<key>NSBonjourServices</key>
<array>
    <string>_ttbdebug._tcp</string>
</array>
```

**Code** — bọc trong `#if DEBUG` để không lọt vào bản production:
```swift
#if DEBUG
TTDebugBridge.shared.start()
#endif
```

Vậy là xong phần cài đặt. Phần còn lại của trang này dành cho lúc đường tự động không hoạt động.

## 4 cách để kết nối

| Cách | Khi nào dùng | Làm thế nào |
|---|---|---|
| **Bonjour (tự động)** | Mặc định — cùng mạng Wi-Fi | Không cần làm gì — tự chạy sau khi gọi `start()` |
| **Nhập tay (Manual Connect)** | Bonjour bị chặn (mạng công ty, VPN) | Vào Debug Bridge panel → **Enter IP** → nhập IP:port của Mac (xem ở TTBDebugPlus → Connection Health) |
| **QR — Ghép nối LAN** | Kết nối nhanh 1 lần, 2 máy ở gần nhau | TTBDebugPlus → Connection Health → quét QR qua **TTBaseDebugKit → SCAN QR CODE** (nhanh nhất) hoặc **Debug Bridge → Scan QR** |
| **QR — Cấu hình Relay** *(mới)* | Khác mạng (làm từ xa/WFH), hoặc muốn tự kết nối mỗi lần mở app mà không cần nhập lại | TTBDebugPlus → Settings → Relay → quét 1 lần qua **TTBaseDebugKit → SCAN QR CODE** hoặc Debug Bridge → Scan QR. Lưu vĩnh viễn — tự kết nối lại mỗi lần mở app sau, kể cả sau khi build lại |

Nhập tay và cả 2 loại QR chạy **song song** với Bonjour, không thay thế — nếu có nhiều đường cùng tìm ra kết nối, tất cả đều được giữ (thiết kế có chủ đích, không phải lỗi).

**Set relay bằng code thay vì quét QR:**
```swift
TTDebugBridge.shared.config.relayHost = "192.168.1.10"
TTDebugBridge.shared.config.relayPort = 51820
```
Relay set bằng code kiểu này luôn được ưu tiên hơn bất kỳ cấu hình nào đã lưu từ QR trước đó.

## Làm sao biết đang kết nối qua kênh nào

Mở TTBDebugPlus — mỗi thiết bị trong sidebar có 1 icon màu nhỏ:
- 🔵 **Bonjour** — kết nối trực tiếp trong mạng LAN
- 🟣 **Relay** — kết nối qua Relay Server của chính Mac này
- 🟣 (mờ hơn) **Relay (Remote)** — đang xem 1 thiết bị thực ra đang nối vào **Mac khác**, thông qua Relay Client của mình

Icon tự cập nhật nếu thiết bị đổi kênh (vd rớt Wi-Fi rồi tự nối lại qua relay đã cấu hình).

## Xử lý sự cố nhanh (3 lỗi hay gặp)

| Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|
| Console báo `NoAuth -65555` | Thiếu/sai key trong Info.plist | Thêm đủ 2 key ở trên, xoá app khỏi máy, chạy lại |
| Thiết bị không hiện trong TTBDebugPlus | Không cùng Wi-Fi, hoặc Server chưa bật trên Mac | Kiểm tra 2 máy cùng mạng; kiểm tra menu bar TTBDebugPlus có hiện "Server Running" |
| Debug Bridge panel báo **"Permission Denied"** | iOS đã từ chối quyền Local Network | Bấm **Open Settings** ngay trong panel → bật Local Network → quay lại app bấm **Reset Connection** |

Chi tiết hơn: xem mục Troubleshooting trong `README.md`, hoặc tab **Integration Guide** ngay trong TTBDebugPlus.
