# GameTranslator iPhone sürümü: kurulum

iPhone sürümü App Store'da değil. İmzasız bir IPA dosyası olarak dağıtılır; her kullanıcı kendi sertifikasıyla imzalayıp
kurar (Feather, Sideloadly, AltStore gibi araçlarla).

## Gerekenler

- iOS 26 veya üstü bir iPhone (iOS 15 ve sonrasında çalışır; internetsiz çeviri iOS 26 ister).
- PS5, telefon ve TV aynı Wi-Fi ağında.
- TV'de GameTranslator TV uygulaması (LG, Samsung, Android TV; kurulum: `docs/tv-kurulum.md`).
- PS5'te şifresiz bir ikinci kullanıcı ve onun PSN hesabı (kumanda TV'de kalsın diye).

## Kurulum

1. `GameTranslator-iOS-<sürüm>.ipa` dosyasını telefona ya da imzalama aracına aktar.
2. Feather (ya da kullandığın araç) ile kendi sertifikanla imzala ve kur.
3. iPhone'da **Ayarlar › Genel › VPN ve Cihaz Yönetimi**'nden sertifikana güven (aracın istediği gibi).
4. Uygulamayı aç. **"Yerel ağdaki cihazları bulmak istiyor"** sorusuna **İzin Ver** de. Bu izin olmadan PS5 ve TV
   bulunamaz. Yanlışlıkla reddettiysen: **Ayarlar › Gizlilik ve Güvenlik › Yerel Ağ › GameTranslator**.

## İlk kullanım

1. **PSN ile giriş yap.** PS5'teki ikinci kullanıcının hesabını kullan.
2. **PS5'i eşleştir:**
   - PS5'te ikinci kullanıcıdayken Ayarlar › Sistem › Uzaktan Oynatma › Cihaz Eşleştir'i aç.
   - Telefonda PS5'i seç ve ekrandaki 8 haneli kodu gir.
   - Telefonun sayı klavyesinde nokta yerine virgül çıkarsa sorun değil, uygulama noktaya çevirir.
3. **TV'de GameTranslator'ı aç.** TV telefonu kendisi bulur; ilk seferde 30–40 saniye sürebilir.
4. **Telefonda büyük düğmeye bas.** Çeviri başlar. Ekranı kilitleyebilirsin, çeviri sürer.
5. **TV'den ses gelmezse:** PS5'te PS tuşuna bas, alttaki menüden Ses › Çıkış Cihazı'nı aç ve HDMI'ı seç. Bu bir kez
   yapılır.

## Ayarlar

- **Çeviri motoru:**
  - **Google:** Anahtarsız, varsayılan.
  - **DeepL:** Kendi anahtarınla.
  - **Google Gemini:** Yapay zekâ, ücretsiz anahtarla; anahtarı ayarlardaki bağlantıdan al ve "Kaydet ve dene"ye bas.
  - **Cihazda (Apple Çeviri, internetsiz):** iPhone Ayarlar › Uygulamalar › Çeviri › İndirilen Diller'den İngilizce
    ve Türkçe'yi indir.
- **Oyun paketleri:** GTA V, RDR2, Elden Ring, Mafia: The Old Country ve başkalarının hazır Türkçesi; açık kalması
  önerilir. Uygulama hangi oyunu oynadığını kendisi anlar.
- **Tuş yazılarını gizle:** "SKIP", "RESUME" gibi düğme yazıları çevrilmez; bir sorun çıkarırsa kapat.
- **Altyazı bölgesi:** Oyunun altyazısının arandığı yer. İki satırlık altyazılar yarım geliyorsa üst kenarı biraz yukarı
  çek.
- **Altyazının yeri, "Oyunun altyazısını örterek":** Çeviri, oyunun altyazısının üstünde, aynı boyda, koyu bir bantla
  çıkar.

## Bilinen sınırlar

- Telefondan TV uygulaması kurma iPhone'da henüz yok; TV uygulaması bilgisayardan ya da Android telefondan kurulur.
- Kendin derlemek istersen: `mobile/ios` ve `docs/ios-notlar.md`. Gerekenler:
  - Xcode
  - Flutter
  - `mobile/ios/scripts/fetch-libchiaki.sh` ile indirilen libchiaki
