# Trip 🗺️

Gezdiğin yerleri haritada boyayan, her şehre tarihli geziler, fotoğraflar, videolar ve notlar iliştirebildiğin bir iOS uygulaması.

> Durum: MVP geliştirme aşamasında.

## Özellikler (MVP)

- **Harita seç:** Türkiye (81 il) veya Dünya (ülkeler). Gezdikçe harita boyanır.
- **İşaretle ve gezi aç:** Bir ile/ülkeye dokun, "gittim" olarak işaretle, o yere istediğin kadar tarihli gezi ekle.
- **Fotoğraf, video, not:** Galerinden medya ekle, gezine notlar yaz.
- **İlerleme ve grafikler:** "Türkiye'nin %28'ini gezdin", coğrafi bölgelere/kıtalara göre yüzdeler, yıllara göre geziler.
- **Otomatik gezi bulma:** Galerideki fotoğrafların konum ve tarih bilgisinden gezilerini tamamen cihaz üzerinde (internetsiz) tespit eder.

## Geliştirme

Gereksinimler: Xcode 26+ (iOS 18 SDK ve üstü), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate        # project.yml → Trip.xcodeproj
open Trip.xcodeproj
```

`Trip.xcodeproj` repoda da bulunduğu için XcodeGen olmadan da açılabilir; ancak dosya ekleyip çıkardıktan sonra `xcodegen generate` çalıştır.
Gerçek cihazda çalıştırmak için Xcode'da *Signing & Capabilities* altından kendi takımını seç.

## Lisans / Veri

Harita sınırları [Natural Earth](https://www.naturalearthdata.com/) verisinden üretilmiştir (public domain).
