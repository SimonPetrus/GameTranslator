# iOS yerel katmanı: libchiaki

iOS fizibilite adımı 1. Bu klasör libchiaki'yi (chiaki-ng) ve bağımlılıklarını **iOS cihaz hedefi
(arm64, iphoneos SDK)** için statik kütüphane olarak derler. Ardından `linktest/gt_ios_linktest.c` dosyasını
bağlayarak sembollerin gerçekten çözüldüğünü kanıtlar. Bu dosya arama, uyandırma, kayıt, oturum ve PSN/holepunch
için gerçek chiaki işlevlerini çağırır. Simülatör, VideoToolbox çözücüsü, Swift ve Flutter kabuğu bu adımın
dışındadır.

## Derleme

Gerekenler: macOS, Xcode (komut satırı araçlarıyla), CMake 3.24 veya üstü, Python 3 ve internet bağlantısı.
OpenSSL'in derleme sistemi boşluk içeren yolları desteklemez. Depo yolunda boşluk varsa `GT_WORK_DIR`
değişkenini boşluksuz bir klasöre yönlendirin.

```sh
./mobile/ios-native/build.sh        # depo kökünden
```

Betik şunları yapar. Geçici dosyaların ve çıktıların hepsi `work/ios-native/` altına yazılır.

1. `third-party/chiaki-ng` yoksa chiaki-ng **v1.10.1** sürümünü (`f30da0aa…`) yalnız gereken alt
   modüllerle (curl, gf-complete, jerasure, nanopb) indirir. Klasör varsa ve başka bir commit'teyse durur.
   Bunu `GT_ALLOW_CHIAKI_MISMATCH=1` ile geçebilirsiniz.
2. `patches/*.patch` dosyalarını, varsa, chiaki-ng'ye uygular. Şu an yama gerekmiyor.
3. nanopb üreteci için bir Python sanal ortamı kurar (`protobuf`, `grpcio-tools`; sürümler sabit).
   protoc olarak nanopb'nin grpcio-tools sarmalayıcısı kullanılır, ayrıca protoc kurmak gerekmez.
4. OpenSSL'i kaynaktan derler (`scripts/build-openssl.sh`). Arşiv SHA-256 ile doğrulanır.
5. CMake ile derler (`cmake/ios-arm64.toolchain.cmake`, Unix Makefiles; imzalama gerekmez).
6. Bağlamayı doğrular (`scripts/verify-link.sh`) ve `work/ios-native/out/LINK_REPORT.md` raporunu yazar.

GitHub Actions'ta aynı betik `.github/workflows/ios-native.yml` ile çalışır. Çıktı klasörü
`libchiaki-ios-arm64` adlı artifact olarak yüklenir.

## Çıktılar (`work/ios-native/out/`)

- `lib/libgtchiaki_ios.a`: aşağıdakilerin hepsini içeren tek arşiv. Xcode'a eklenecek olan budur.
- `lib/`: tek tek statik kütüphaneler: `libchiaki`, `libjerasure`, `libgf_complete`, `libprotobuf-nanopb`,
  `libcurl`, `libjson-c`, `libminiupnpc`, `libevent_core`, `libssl` ve `libcrypto`.
- `include/`: chiaki başlıkları ve üretilmiş `chiaki/config.h`.
- `LINK_REPORT.md`: Mach-O/arm64/iOS platform kontrolü, bağlanan nesneler ve gereken sistem çerçeveleri.

Uygulamayı bağlarken sistem tarafında gerekenleri (ör. `-framework SystemConfiguration`, `CoreFoundation`,
`CoreServices`) `LINK_REPORT.md` dosyasındaki "ek bağlayıcı bayrakları" satırı listeler.

## Kararlar

- **OpenSSL kaynaktan derlenir.** Sürüm 3.5.9 LTS'dir ve SHA-256 değeri sabitlenmiştir. Hazır ikili paketler
  üçüncü bir tarafa güvenmeyi gerektirir ve sürüm takibini zorlaştırır. Kaynaktan derleme ise OpenSSL'in kendi
  `ios64-xcrun` hedefiyle tek komuttur. CI'da sonuç önbelleğe alınır, bu yüzden yalnız ilk koşu uzun sürer.
- **libevent kaynaktan derlenir (2.1.12-stable, yalnız statik `event_core`).** chiaki-ng,
  `CHIAKI_ENABLE_ANDROID` kapalıyken `remote/holepunch.c` (PSN üzerinden bağlantı) için libevent ister.
  Android'de bu kod yolu derlenmez. `cmake/Findlibevent.cmake`, chiaki-ng'nin `find_package(libevent)`
  çağrısını bu derlemeye yönlendirir.
- json-c 0.17 ve miniupnpc 2.2.8, Android'deki gibi FetchContent ile alınır. URL_HASH ile sabitlenmiştir.
- Mac'teki Homebrew kütüphaneleri macOS içindir. Araç zinciri `/opt/homebrew` ve `/usr/local` yollarını
  aramaz, pkg-config da boş bir arama yoluna yönlendirilir. Böylece iOS hedefine yanlışlıkla macOS
  kütüphanesi bağlanmaz.
- En düşük iOS sürümü 13.0'dır (Flutter'ın varsayılanı). `GT_IOS_DEPLOYMENT_TARGET` ile değiştirilebilir.

Not: Depo kökündeki `.gitignore` dosyası `*.txt` desenini dışlar. Bu klasördeki `CMakeLists.txt` dosyası
depoya `git add -f` ile eklenmiştir.
