// SPDX-License-Identifier: AGPL-3.0-only
import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'l10n.dart';
import 'main.dart';
import 'tv_install_page.dart';
import 'ui.dart';

/// Ayrıntılı kullanım rehberi: PS5 hazırlığından sorun gidermeye kadar her adım. iOS ayarlarındaki gibi bölüm
/// listesi ve her bölümün kendi sayfası. TV kurulum adımları docs/tv-kurulum.md ile aynıdır.
class GuideChapter {
  const GuideChapter({required this.icon, required this.color, required this.title, required this.subtitle, required this.children});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> children;
}

/// Rehber sekmesi: bölüm listesi.
class GuideTab extends StatelessWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context) {
    return LargeTitleList(
      title: L.t('Rehber', 'Guide'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(L.t('Kurulumdan sorun gidermeye kadar her şey, adım adım.', 'Everything from setup to troubleshooting, step by step.'), style: Txt.body.copyWith(color: Tokens.textSecondary)),
        ),
        const GuideList(),
      ],
    );
  }
}

/// Bölümlerin gruplu listesi; satıra dokununca bölüm sayfası açılır.
class GuideList extends StatelessWidget {
  const GuideList({super.key});

  @override
  Widget build(BuildContext context) {
    final chapters = guideChapters(null);
    Widget cell(int index) => Cell(
          icon: chapters[index].icon,
          iconColor: chapters[index].color,
          title: chapters[index].title,
          subtitle: chapters[index].subtitle,
          chevron: true,
          onTap: () => Navigator.of(context).push(appleRoute<void>((_) => GuideChapterPage(index: index))),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(L.t('BAŞLANGIÇ', 'GETTING STARTED')),
        Group(inset: 60, children: [for (var i = 0; i < 5; i++) cell(i)]),
        GroupHeader(L.t('KULLANIM', 'USAGE')),
        Group(inset: 60, children: [for (var i = 5; i < 8; i++) cell(i)]),
        GroupHeader(L.t('YARDIM', 'HELP')),
        Group(inset: 60, children: [cell(8)]),
      ],
    );
  }
}

/// Tek bir bölümün sayfası. Kurulumdaki yardım düğmesi doğrudan ilgili bölümü açar.
class GuideChapterPage extends StatefulWidget {
  const GuideChapterPage({super.key, required this.index});

  final int index;

  @override
  State<GuideChapterPage> createState() => _GuideChapterPageState();
}

class _GuideChapterPageState extends State<GuideChapterPage> {
  String? address;

  @override
  void initState() {
    super.initState();
    Bridge.state().then((state) {
      if (mounted) setState(() => address = state.localAddress);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chapters = guideChapters(address);
    final chapter = chapters[widget.index];
    final next = widget.index + 1 < chapters.length ? widget.index + 1 : null;
    return GlassScaffold(
      title: L.t('Rehber', 'Guide'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Row(
              children: [
                IconTile(chapter.icon, chapter.color, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chapter.title, style: Txt.title2),
                      Text(chapter.subtitle, style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Glass(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: chapter.children),
          ),
          if (next != null) ...[
            GroupHeader(L.t('SONRAKİ BÖLÜM', 'NEXT CHAPTER')),
            Group(
              inset: 60,
              children: [
                Cell(
                  icon: chapters[next].icon,
                  iconColor: chapters[next].color,
                  title: chapters[next].title,
                  subtitle: chapters[next].subtitle,
                  chevron: true,
                  onTap: () => Navigator.of(context).pushReplacement(appleRoute<void>((_) => GuideChapterPage(index: next))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bölümlerin içeriği. [address]: telefonun ağ adresi (OBS adresini tam yazmak için); bilinmiyorsa genel yazılır.
List<GuideChapter> guideChapters(String? address) {
  final phone = address ?? L.t('telefonun adresi', 'your phone\'s address');
  return [
    GuideChapter(
      icon: CupertinoIcons.arrow_right_arrow_left,
      color: Tokens.accent,
      title: L.t('Nasıl çalışır?', 'How does it work?'),
      subtitle: L.t('Bir bakışta bütün düzen', 'The whole setup at a glance'),
      children: [
        _P(L.t(
          'GameTranslator üç cihazı birbirine bağlar. Oyun PS5\'te çalışır, sen TV\'de oynarsın; telefon arada çevirmenlik yapar:',
          'GameTranslator connects three devices. The game runs on the PS5 and you play on the TV; the phone translates in between:',
        )),
        _Steps([
          L.t(
            'Telefon, oyun görüntüsünü PS5\'ten Remote Play (Uzaktan Oynatma) ile alır. Kamera kullanılmaz.',
            'The phone receives the game video from the PS5 over Remote Play. No camera is used.',
          ),
          L.t(
            'Görüntüde altyazının çıktığı bölgeyi okur ve yazıyı çevirir.',
            'It reads the area of the picture where subtitles appear and translates the text.',
          ),
          L.t(
            'Çeviriyi aynı Wi-Fi\'deki TV\'ye gönderir. TV\'deki GameTranslator uygulaması onu oyunun üstünde gösterir.',
            'It sends the translation to the TV on the same Wi-Fi. The GameTranslator app on the TV shows it over the game.',
          ),
        ]),
        _Sub(L.t('Neler gerekli?', 'What do you need?')),
        _Bullets([
          L.t('PS5 ve üzerinde ikinci bir kullanıcı (aşağıda anlatılıyor).', 'A PS5 with a second user on it (explained below).'),
          L.t(
            'GameTranslator TV uygulamasının kurulu olduğu bir TV: LG, Samsung ya da Android TV / Google TV.',
            'A TV with the GameTranslator TV app installed: LG, Samsung or Android TV / Google TV.',
          ),
          L.t(
            'Telefon, PS5 ve TV\'nin bağlı olduğu tek bir ev ağı (Wi-Fi).',
            'A single home network (Wi-Fi) that the phone, PS5 and TV are all connected to.',
          ),
          L.t(
            'Çevrimiçi çeviri için internet. İnternetsiz çalışan bir çeviri seçeneği de var.',
            'Internet access for online translation. There is also a translation option that works offline.',
          ),
        ]),
        _Tip(L.t(
          'Kurulum bir kez yapılır. Sonrasında tek yapacağın: çeviriyi başlatmak ve TV\'de uygulamayı açmak.',
          'Setup is done once. After that all you do is start the translation and open the app on the TV.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.gamecontroller_fill,
      color: Tokens.indigo,
      title: L.t('PS5\'i hazırla', 'Prepare the PS5'),
      subtitle: L.t('İkinci kullanıcı ve Uzaktan Oynatma', 'Second user and Remote Play'),
      children: [
        _Sub(L.t('1. İkinci bir kullanıcı ekle', '1. Add a second user')),
        _P(L.t(
          'PS5, Uzaktan Oynatma ile bağlanan cihazı o kullanıcının kumandası sayar. Telefon senin hesabınla bağlanırsa '
              'elindeki kumanda TV\'den kopar. Bu yüzden telefon ayrı bir kullanıcıyla bağlanır; sen kendi hesabınla oynamaya devam edersin.',
          'The PS5 treats a device connected through Remote Play as that user\'s controller. If the phone connects with your account, '
              'the controller in your hands gets disconnected from the TV. That is why the phone connects with a separate user, '
              'and you keep playing with your own account.',
        )),
        _Steps([
          L.t(
            'PS5\'te yeni bir kullanıcı ekle (ana ekrandaki profil resminden Kullanıcı Değiştir › Kullanıcı Ekle).',
            'Add a new user on the PS5 (from your profile picture on the home screen: Switch User › Add User).',
          ),
          L.t(
            'Bu kullanıcıya bir PSN hesabıyla giriş yap. Hesabın yoksa ücretsiz açabilirsin; PS Plus gerekmez.',
            'Sign this user in with a PSN account. If you do not have one you can create it for free; PS Plus is not required.',
          ),
          L.t(
            'Telefonda PSN girişini de bu ikinci hesapla yapacaksın.',
            'You will also sign in to PSN on the phone with this second account.',
          ),
        ]),
        _Sub(L.t('2. Uzaktan Oynatmayı aç', '2. Turn on Remote Play')),
        _Steps([
          L.t('PS5\'te ikinci kullanıcıya geç.', 'Switch to the second user on the PS5.'),
          L.t('Ayarlar › Sistem › Uzaktan Oynatma\'ya gir.', 'Go to Settings › System › Remote Play.'),
          L.t('"Uzaktan Oynatmayı Etkinleştir"i aç.', 'Turn on "Enable Remote Play".'),
        ]),
        _Sub(L.t('3. Dinlenme modundan uyandırma (isteğe bağlı)', '3. Waking from rest mode (optional)')),
        _P(L.t(
          'PS5 dinlenme modundayken çeviriyi başlattığında telefonun onu uyandırabilmesi için:',
          'So that the phone can wake the PS5 when you start the translation while it is in rest mode:',
        )),
        _Steps([
          L.t(
            'Ayarlar › Sistem › Güç Tasarrufu › Dinlenme Modunda Kullanılabilen Özellikler\'e gir.',
            'Go to Settings › System › Power Saving › Features Available in Rest Mode.',
          ),
          L.t(
            '"İnternete Bağlı Kal" ve "PS5\'in Ağdan Açılmasını Etkinleştir" seçeneklerini aç.',
            'Turn on "Stay Connected to the Internet" and "Enable Turning On PS5 from Network".',
          ),
        ]),
        _Tip(L.t(
          'Uyandırmayı istemiyorsan telefonda Ayarlar › PS5 › "Dinlenme modundaysa uyandır"ı kapatabilirsin.',
          'If you do not want the wake-up, you can turn off Settings › PS5 › "Wake if in rest mode" on the phone.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.link,
      color: Tokens.success,
      title: L.t('Telefonu PS5 ile eşleştir', 'Pair the phone with the PS5'),
      subtitle: L.t('PSN girişi ve 8 haneli kod', 'PSN sign-in and the 8-digit code'),
      children: [
        _Sub(L.t('1. PSN ile giriş yap', '1. Sign in with PSN')),
        _Steps([
          L.t(
            'Kurulum ekranında "PSN ile giriş yap"a dokun. Sony\'nin kendi giriş sayfası açılır.',
            'On the setup screen tap "Sign in with PSN". Sony\'s own sign-in page opens.',
          ),
          L.t(
            'PS5\'teki ikinci kullanıcının hesabıyla giriş yap.',
            'Sign in with the account of the second user on the PS5.',
          ),
          L.t(
            'Giriş bitince uygulama kuruluma kendiliğinden döner ve "PSN hesabı bağlandı" yazar.',
            'When sign-in finishes the app returns to setup by itself and shows "PSN account linked".',
          ),
        ]),
        _Tip(L.t(
          'Şifren doğrudan Sony\'ye gider; uygulama yalnızca hesabının kimlik numarasını saklar.',
          'Your password goes straight to Sony; the app only stores your account\'s ID number.',
        )),
        _Sub(L.t('2. Eşleştirme kodunu gir', '2. Enter the pairing code')),
        _Steps([
          L.t(
            'PS5\'te ikinci kullanıcıdayken Ayarlar › Sistem › Uzaktan Oynatma › "Cihaz Eşleştir"e gir.',
            'While on the second user on the PS5, go to Settings › System › Remote Play › "Link Device".',
          ),
          L.t(
            'Ekranda 8 haneli bir kod ve geri sayım görünür. Kod yaklaşık 5 dakika geçerlidir.',
            'An 8-digit code and a countdown appear on the screen. The code is valid for about 5 minutes.',
          ),
          L.t(
            'Telefonda "Bulunan konsol" listesinden PS5\'ini seç.',
            'On the phone, pick your PS5 from the "Consoles found" list.',
          ),
          L.t('Kodu kutulara yaz ve "Eşleştir"e dokun.', 'Type the code into the boxes and tap "Pair".'),
        ]),
        _Sub(L.t('PS5 listede yoksa', 'If the PS5 is not in the list')),
        _Bullets([
          L.t(
            'Telefon ve PS5 aynı Wi-Fi ağında mı kontrol et; misafir ağı ya da mobil veri olmamalı.',
            'Check that the phone and PS5 are on the same Wi-Fi network; it must not be a guest network or mobile data.',
          ),
          L.t('"Yenile"ye dokun.', 'Tap "Refresh".'),
          L.t(
            'Yine çıkmazsa "IP adresini elle yaz"a dokun. Adres PS5\'te Ayarlar › Ağ › Bağlantı Durumu › Bağlantı Durumunu Görüntüle\'de yazar.',
            'If it still does not show up, tap "Enter IP address manually". The address is on the PS5 under Settings › Network › Connection Status › View Connection Status.',
          ),
        ]),
        _Tip(L.t(
          'Eşleştirme bir kez yapılır. PS5\'in adresi değişirse uygulama onu ağda yeniden bulur.',
          'Pairing is done once. If the PS5\'s address changes, the app finds it again on the network.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.tv_fill,
      color: Tokens.purple,
      title: L.t('TV\'yi hazırla', 'Prepare the TV'),
      subtitle: L.t('Desteklenen TV\'ler ve TV uygulaması', 'Supported TVs and the TV app'),
      children: [
        _P(L.t(
          'Altyazıyı TV\'de gösteren ayrı bir GameTranslator TV uygulaması vardır. Henüz mağazalarda olmadığı için TV\'ye '
              'bir kez kurulur. LG ve Android TV\'ye bu telefondan kurabilirsin; Samsung\'a kurulum şimdilik bilgisayardan yapılır.',
          'A separate GameTranslator TV app shows the subtitles on the TV. Because it is not in the app stores yet, it is '
              'installed on the TV once. You can install it on LG and Android TV from this phone; for Samsung the installation is done from a computer for now.',
        )),
        const InstallTvButton(),
        _Sub(L.t('Hangi TV\'ler destekleniyor?', 'Which TVs are supported?')),
        _Table([
          ('LG', L.t('webOS 4 ve üstü', 'webOS 4 and later'), true),
          ('Samsung', L.t('Tizen, 2019 ve sonrası', 'Tizen, 2019 and later'), true),
          (
            'Android TV / Google TV',
            L.t('Vestel, Arçelik, Beko, Grundig, Philips, Sony, TCL ve diğerleri', 'Vestel, Arçelik, Beko, Grundig, Philips, Sony, TCL and others'),
            true,
          ),
          (
            L.t('Diğerleri', 'Others'),
            L.t(
              'Vestel/Arçelik/Beko/Grundig\'in Linux modelleri, Philips Saphi, Titan OS',
              'Linux models of Vestel/Arçelik/Beko/Grundig, Philips Saphi, Titan OS',
            ),
            false,
          ),
        ]),
        _Tip(L.t(
          'TV\'n Android mi? Ana ekranında Google Play Store ya da "Google TV" yazıyorsa Android\'dir.',
          'Is your TV Android? If its home screen says Google Play Store or "Google TV", it is Android.',
        )),
        const _Sub('LG'),
        _Steps([
          L.t(
            'Bilgisayardan webostv.developer.lge.com adresinde ücretsiz bir LG geliştirici hesabı aç.',
            'On a computer, create a free LG developer account at webostv.developer.lge.com.',
          ),
          L.t(
            'TV\'de LG Content Store\'dan "Developer Mode" uygulamasını kur, hesabınla giriş yap ve "Dev Mode Status"u aç. TV yeniden başlar.',
            'On the TV, install the "Developer Mode" app from the LG Content Store, sign in with your account and turn on "Dev Mode Status". The TV restarts.',
          ),
          L.t(
            'TV\'de Developer Mode uygulamasında "Key Server"ı aç.',
            'In the Developer Mode app on the TV, turn on "Key Server".',
          ),
          L.t(
            'Telefonda "TV uygulamasını kur" sihirbazında LG\'yi seç, TV\'ni bul ve ekrandaki 6 karakterli parolayı yaz '
                '(bilgisayardaki GameTranslator\'ın TV adımı da aynısını yapar).',
            'In the "Install the TV app" wizard on the phone, choose LG, find your TV and type the 6-character passphrase shown on screen '
                '(the TV step of GameTranslator on the computer does the same).',
          ),
        ]),
        _P(L.t(
          'LG\'de geliştirici modu en çok 1000 saat açık kalır. Uzun süre kullanmayacaksan süre dolmadan Developer Mode '
              'uygulamasında "EXTEND"e bas; süre dolarsa TV uygulaması silinir ve baştan kurman gerekir.',
          'On LG, developer mode stays on for 1000 hours at most. If you will not use it for a long time, press "EXTEND" in the '
              'Developer Mode app before the time runs out; if it expires, the TV app is removed and you have to install it again.',
        )),
        const _Sub('Samsung'),
        _Steps([
          L.t(
            'TV\'de Uygulamalar ekranını aç ve kumandayla 1 2 3 4 5 tuşlarına bas. Geliştirici modu penceresi açılır.',
            'On the TV, open the Apps screen and press 1 2 3 4 5 on the remote. The developer mode window opens.',
          ),
          L.t(
            '"Developer mode"u aç, "Host PC IP" alanına bilgisayarının adresini yaz.',
            'Turn on "Developer mode" and enter your computer\'s address in the "Host PC IP" field.',
          ),
          L.t(
            'TV\'yi güç tuşunu basılı tutarak tam kapatıp aç.',
            'Fully turn the TV off by holding the power button, then turn it on again.',
          ),
          L.t(
            'Bilgisayardaki GameTranslator\'ın TV adımında TV\'ni seç. Açılan sayfada ücretsiz bir Samsung hesabıyla giriş yap; uygulama imzalanıp kurulur.',
            'In the TV step of GameTranslator on the computer, pick your TV. On the page that opens, sign in with a free Samsung account; the app is signed and installed.',
          ),
        ]),
        const _Sub('Android TV / Google TV'),
        _Steps([
          L.t(
            'TV\'de Ayarlar › Cihaz Tercihleri › Hakkında\'ya gir (Google TV\'de Ayarlar › Sistem › Hakkında).',
            'On the TV go to Settings › Device Preferences › About (on Google TV: Settings › System › About).',
          ),
          L.t(
            '"Yapı numarası"nın üstünde Tamam tuşuna 7 kez bas.',
            'Press OK 7 times on "Build number".',
          ),
          L.t(
            'Geliştirici seçenekleri\'nden "USB hata ayıklama"yı (varsa "Ağ hata ayıklama"yı da) aç.',
            'In Developer options, turn on "USB debugging" (and "Network debugging" too, if there is one).',
          ),
          L.t(
            'Telefonda "TV uygulamasını kur" sihirbazında "Android TV / Google TV"yi seç ve TV\'deki izin sorusunu onayla.',
            'In the "Install the TV app" wizard on the phone, choose "Android TV / Google TV" and accept the permission prompt on the TV.',
          ),
        ]),
        _P(L.t(
          'TV ağdan hata ayıklamaya izin vermiyorsa USB bellekle de kurabilirsin: GameTranslator\'ın sürümler sayfasından '
              'TV uygulamasının APK dosyasını indir, belleğe kopyala ve TV\'de bir dosya yöneticisiyle açıp kur.',
          'If the TV does not allow debugging over the network, you can also install with a USB stick: download the TV app\'s APK file from '
              'the GameTranslator releases page, copy it to the stick, and open it with a file manager on the TV to install.',
        )),
        _Sub(L.t('Kurulduktan sonra', 'After installing')),
        _P(L.t(
          'TV uygulaması telefonu ağda kendisi bulur; telefona TV\'nin adresini yazman gerekmez. Samsung\'da bilgisayara '
              'yalnızca kurulum için ihtiyaç var; sonrasında kapalı kalabilir.',
          'The TV app finds the phone on the network by itself; you do not need to type the TV\'s address on the phone. On Samsung the computer '
              'is only needed for installation; afterwards it can stay off.',
        )),
        _Sub(L.t('Yayın yapanlar için: OBS', 'For streamers: OBS')),
        _P(L.t(
          'Çeviri açıkken altyazılar bir web sayfası olarak da sunulur. OBS\'te "Tarayıcı Kaynağı" ekleyip adres olarak '
              'http://$phone:8787/obs yaz (1920×1080). Sayfanın zemini saydamdır; TV\'nin tarayıcısında oyunun üstünde göstermez, '
              'yalnızca yayın ve kayıt düzenleri içindir.',
          'While translation is on, the subtitles are also served as a web page. In OBS add a "Browser Source" and enter '
              'http://$phone:8787/obs as the address (1920×1080). The page background is transparent; it will not show over the game in the TV\'s browser, '
              'it is only meant for streaming and recording setups.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.play_fill,
      color: Tokens.accent,
      title: L.t('İlk kullanım', 'First use'),
      subtitle: L.t('Çeviriyi başlat ve TV\'de gör', 'Start the translation and see it on the TV'),
      children: [
        _Steps([
          L.t(
            'PS5\'te oyunu kendi hesabınla aç ve oyunun ayarlarından altyazıları aç.',
            'Start the game on the PS5 with your own account and turn on subtitles in the game\'s settings.',
          ),
          L.t(
            'Telefonda ana ekrandaki büyük düğmeye dokun. İlk seferde bildirim izni sorulur; izin ver ki çeviri arka planda sürsün.',
            'On the phone, tap the big button on the home screen. The first time, notification permission is requested; allow it so the translation keeps running in the background.',
          ),
          L.t(
            'Durum "Çeviri açık" olunca PS5 kartı "Bağlı" yazar. İlk bağlantı birkaç saniye sürer.',
            'When the status reads "Translation on", the PS5 card says "Connected". The first connection takes a few seconds.',
          ),
          L.t(
            'TV\'de GameTranslator uygulamasını aç. Birkaç saniye içinde telefondaki TV kartı "Bağlı" olur.',
            'Open the GameTranslator app on the TV. Within a few seconds the TV card on the phone shows "Connected".',
          ),
          L.t(
            'TV\'de oyun görüntüsü gelmezse Tamam tuşuyla paneli aç, sol ve sağ tuşlarıyla PS5\'in bağlı olduğu HDMI girişini seç.',
            'If no game picture appears on the TV, open the panel with the OK button and use left and right to choose the HDMI input the PS5 is connected to.',
          ),
          L.t(
            'TV\'den ses gelmezse PS5 sesi Remote Play\'e yönlendirmiştir: PS tuşuna bas, alttaki menüden Ses › Çıkış Cihazı\'nı aç ve HDMI\'ı seç. Bu bir kez yapılır.',
            'If there is no sound from the TV, the PS5 has routed the audio to Remote Play: press the PS button, open Sound › Output Device in the bottom menu and choose HDMI. You only do this once.',
          ),
          L.t(
            'Telefonda "TV\'ye deneme altyazısı gönder"e dokun. TV\'de yazıyı görüyorsan her şey hazır.',
            'On the phone, tap "Send test subtitle to TV". If you see the text on the TV, everything is ready.',
          ),
        ]),
        _Tip(L.t(
          'Çeviri açıkken telefonun ekranını kapatabilirsin. Durdurmak için uygulamadaki düğmeye ya da bildirimdeki "Durdur"a dokun.',
          'You can turn the phone screen off while translating. To stop, tap the button in the app or "Stop" in the notification.',
        )),
        _Sub(L.t('Sonraki seferler', 'Next times')),
        _P(L.t(
          'Yalnızca iki adım: telefonda çeviriyi başlat, TV\'de GameTranslator\'ı aç.',
          'Only two steps: start the translation on the phone and open GameTranslator on the TV.',
        )),
        _Sub(L.t('Pil ve ısınma', 'Battery and heat')),
        _P(L.t(
          'Telefon sürekli video çözüp yazı okur; uzun oturumlarda şarja takılı kullan.',
          'The phone constantly decodes video and reads text; keep it plugged in during long sessions.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.dot_radiowaves_left_right,
      color: Tokens.gray,
      title: L.t('TV kumandası', 'TV remote'),
      subtitle: L.t('TV uygulamasındaki tuşlar', 'Keys in the TV app'),
      children: [
        _P(L.t(
          'TV\'de GameTranslator açıkken kumandanın tuşları şunları yapar:',
          'While GameTranslator is open on the TV, the remote\'s keys do the following:',
        )),
        _Keys([
          (L.t('Tamam', 'OK'), L.t('Durum panelini açar ve kapatır (HDMI girişi, bağlantı durumu).', 'Opens and closes the status panel (HDMI input, connection status).')),
          (L.t('Sol / Sağ', 'Left / Right'), L.t('Panel açıkken HDMI girişini değiştirir.', 'Changes the HDMI input while the panel is open.')),
          ('1 – 4', L.t('HDMI girişini doğrudan seçer.', 'Selects the HDMI input directly.')),
          (L.t('Yukarı / Aşağı', 'Up / Down'), L.t('Altyazıyı ekranda yukarı ya da aşağı kaydırır.', 'Moves the subtitle up or down on the screen.')),
          (L.t('Kırmızı', 'Red'), L.t('TV\'nin kendi deneme yazısını gösterir.', 'Shows the TV\'s own test text.')),
          (L.t('Yeşil', 'Green'), L.t('Durum panelini açar ve kapatır.', 'Opens and closes the status panel.')),
          (L.t('Mavi', 'Blue'), L.t('Örnek altyazılarla tanıtımı başlatır ya da durdurur.', 'Starts or stops the demo with sample subtitles.')),
          (L.t('Geri', 'Back'), L.t('Uygulamadan çıkar.', 'Exits the app.')),
        ]),
        _Tip(L.t(
          'Oyunu PS5 kumandasıyla oynarsın; TV kumandası yalnızca bu ayarlar için gerekir.',
          'You play the game with the PS5 controller; the TV remote is only needed for these settings.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.crop,
      color: Tokens.teal,
      title: L.t('Altyazı bölgesini ayarla', 'Adjust the subtitle area'),
      subtitle: L.t('Telefonun ekranda nereye bakacağı', 'Where the phone looks on the screen'),
      children: [
        _P(L.t(
          'Telefon bütün ekranı değil, yalnızca altyazının çıktığı bölgeyi okur. Bölge yanlış yerdeyse çeviri gelmez ya da '
              'ekrandaki başka yazılar çevrilir.',
          'The phone does not read the whole screen, only the area where subtitles appear. If the area is in the wrong place, no translation '
              'comes through or other text on screen gets translated.',
        )),
        _Steps([
          L.t(
            'Çeviri açıkken oyunda bir altyazı çıkmasını bekle.',
            'With translation on, wait for a subtitle to appear in the game.',
          ),
          L.t(
            'Ana ekrandaki önizlemede mavi çerçeveye bak: altyazının tamamı çerçevenin içinde olmalı.',
            'Look at the blue frame in the preview on the home screen: the whole subtitle must be inside the frame.',
          ),
          L.t(
            'Değilse "Altyazı bölgesini ayarla"ya dokun. Üst, Alt, Sol ya da Sağ kenarı seç ve sürgüyle yerini değiştir.',
            'If not, tap "Adjust subtitle area". Choose the Top, Bottom, Left or Right edge and move it with the slider.',
          ),
          L.t(
            'Ana ekrandaki "Çerçevede okunan" satırı telefonun o anda ne okuduğunu gösterir; altyazının tamamı orada görünmeli.',
            'The "Read in frame" line on the home screen shows what the phone is reading right now; the whole subtitle should appear there.',
          ),
        ]),
        _Bullets([
          L.t('Cümlenin başı ya da sonu kesiliyorsa çerçeveyi genişlet.', 'If the start or end of a sentence is cut off, widen the frame.'),
          L.t(
            'İki satırlı altyazılarda üst satır kayboluyorsa üst kenarı yukarı al.',
            'If the top line disappears in two-line subtitles, move the top edge up.',
          ),
          L.t(
            'Görev yazıları, harita adları gibi başka yazılar çevriliyorsa çerçeveyi daralt.',
            'If other text such as quest text or map names gets translated, narrow the frame.',
          ),
        ]),
        _Tip(L.t(
          'Her oyun altyazıyı farklı yere koyar; yeni bir oyuna başladığında bölgeye bir kez bakmak yeter.',
          'Every game places subtitles differently; when you start a new game, just check the area once.',
        )),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.textformat,
      color: Tokens.warning,
      title: L.t('Çeviri ve görünüm', 'Translation and appearance'),
      subtitle: L.t('Motor, sözlük ve TV\'deki yazı', 'Engine, glossary and text on the TV'),
      children: [
        _Sub(L.t('Çeviri motoru', 'Translation engine')),
        _Keys([
          (
            'Google',
            L.t(
              'İnternet ister, anahtar gerekmez. Çoğu oyun için en iyi başlangıç.',
              'Needs internet, no key required. The best starting point for most games.',
            ),
          ),
          (
            'DeepL',
            L.t(
              'Daha doğal cümleler kurar. DeepL\'den aldığın kendi API anahtarını yazman gerekir.',
              'Produces more natural sentences. You need to enter your own API key from DeepL.',
            ),
          ),
          (
            L.t('Cihazda', 'On device'),
            L.t(
              'İnternetsiz çalışır; kalitesi diğerlerinden düşüktür. İlk kullanımda dil modeli bir kez iner.',
              'Works without internet; its quality is lower than the others. The language model is downloaded once on first use.',
            ),
          ),
        ]),
        _P(L.t(
          'İnternet koparsa çeviri kendiliğinden cihazdaki modele geçer ve bağlantı gelince geri döner.',
          'If the internet drops, translation switches to the on-device model by itself and switches back when the connection returns.',
        )),
        _Sub(L.t('Terim sözlüğü', 'Glossary')),
        _P(L.t(
          'Çevirinin bozduğu karakter adlarını ve oyun terimlerini sabitlemek içindir (yalnız İngilizce → Türkçe). '
              'Ayarlar › Çeviri › Terim sözlüğü\'nden açılır. "terms" içindeki terimler yazdığın Türkçeyle çevrilir, '
              '"keep" içindeki adlar olduğu gibi kalır.',
          'It is for fixing character names and game terms that the translation gets wrong (English → Turkish only). '
              'Open it from Settings › Translation › Glossary. Terms under "terms" are translated with the Turkish you write, '
              'and names under "keep" stay as they are.',
        )),
        _Sub(L.t('TV\'deki görünüm', 'Appearance on the TV')),
        _Bullets([
          L.t('Yazı boyutu ve rengi: Ayarlar › TV\'de görünüm.', 'Text size and color: Settings › Appearance on TV.'),
          L.t(
            'Altyazının yeri: oyunun altyazısını örterek, üstünde, altında ya da ekranın altında sabit.',
            'Subtitle position: covering the game\'s subtitle, above it, below it, or fixed at the bottom of the screen.',
          ),
          L.t(
            'Zemin koyuluğu: yazının arkasındaki siyah kutunun koyuluğu. Oyunun altyazısını örtüyorsan yüksek tut.',
            'Background darkness: how dark the black box behind the text is. Keep it high if you are covering the game\'s subtitle.',
          ),
        ]),
      ],
    ),
    GuideChapter(
      icon: CupertinoIcons.wrench_fill,
      color: Tokens.danger,
      title: L.t('Sorun giderme', 'Troubleshooting'),
      subtitle: L.t('Sık karşılaşılan durumlar', 'Common situations'),
      children: [
        _Qa(L.t('Çeviri başlamıyor, "PS5\'e bağlanılıyor"da kalıyor', 'Translation does not start, stuck on "Connecting to PS5"'), [
          L.t(
            'PS5 açık mı? Dinlenme modundaysa uyandırma ayarlarını "PS5\'i hazırla" bölümündeki gibi aç.',
            'Is the PS5 on? If it is in rest mode, turn on the wake-up settings as described in "Prepare the PS5".',
          ),
          L.t('Telefon Wi-Fi\'ye bağlı ve PS5 ile aynı ağda mı?', 'Is the phone connected to Wi-Fi and on the same network as the PS5?'),
          L.t('PS5\'te Uzaktan Oynatma açık mı?', 'Is Remote Play turned on on the PS5?'),
        ]),
        _Qa(L.t('"Uzaktan Oynatma başka bir cihaz tarafından kullanılıyor"', '"Remote Play is being used by another device"'), [
          L.t(
            'PS5 aynı anda tek bir Uzaktan Oynatma bağlantısı kabul eder. Bilgisayardaki GameTranslator ya da başka bir Remote Play uygulaması açıksa kapat.',
            'The PS5 accepts only one Remote Play connection at a time. If GameTranslator on the computer or another Remote Play app is open, close it.',
          ),
          L.t(
            'Az önce durdurduysan birkaç saniye bekle; uygulama kendiliğinden yeniden dener.',
            'If you just stopped it, wait a few seconds; the app retries by itself.',
          ),
        ]),
        _Qa(L.t('Kumandam TV\'den koptu', 'My controller disconnected from the TV'), [
          L.t(
            'Telefon senin oynadığın hesapla bağlanmış. Ayarlar › PS5 › "PSN hesabını değiştir" ile ikinci kullanıcının hesabına geç.',
            'The phone has connected with the account you are playing on. Use Settings › PS5 › "Change PSN account" to switch to the second user\'s account.',
          ),
        ]),
        _Qa(L.t('TV kartı "Bekleniyor"da kalıyor', 'The TV card stays on "Waiting"'), [
          L.t('TV\'de GameTranslator uygulaması açık mı?', 'Is the GameTranslator app open on the TV?'),
          L.t(
            'TV, telefonla aynı ağda mı? Misafir ağı ya da farklı bir modem olmamalı.',
            'Is the TV on the same network as the phone? It must not be a guest network or a different modem.',
          ),
          L.t(
            'Bilgisayardaki GameTranslator açıksa kapat; TV ağda ilk bulduğuna bağlanır.',
            'If GameTranslator on the computer is open, close it; the TV connects to the first one it finds on the network.',
          ),
          L.t(
            'TV uygulaması daha önce bilgisayara bağlandıysa o adreste takılı kalmış olabilir. Aşağıdaki "TV telefonu bulamıyorsa" adımlarını uygula.',
            'If the TV app was connected to the computer before, it may be stuck on that address. Follow the "If the TV cannot find the phone" steps below.',
          ),
        ]),
        _Sub(L.t('TV telefonu bulamıyorsa', 'If the TV cannot find the phone')),
        ...tvRecoverySteps,
        _Qa(L.t('TV\'de oyun görüntüsü yok, ekran siyah', 'No game picture on the TV, the screen is black'), [
          L.t(
            'Tamam ile paneli aç ve sol/sağ ile PS5\'in bağlı olduğu HDMI girişini seç.',
            'Open the panel with OK and choose the HDMI input the PS5 is connected to using left/right.',
          ),
          L.t(
            'Bazı Android TV\'ler HDMI görüntüsünü başka uygulamaya vermez; o TV\'lerde altyazı görünür ama arkası siyah kalır.',
            'Some Android TVs do not hand the HDMI picture to another app; on those TVs the subtitles show but the background stays black.',
          ),
        ]),
        _Qa(L.t('Altyazı hiç gelmiyor', 'No subtitles at all'), [
          L.t('Oyunun kendi altyazıları açık mı?', 'Are the game\'s own subtitles turned on?'),
          L.t(
            'Ana ekrandaki "Çerçevede okunan" boşsa bölge yanlış yerdedir; "Altyazı bölgesini ayarla" bölümüne bak.',
            'If "Read in frame" on the home screen is empty, the area is in the wrong place; see the "Adjust the subtitle area" section.',
          ),
          L.t(
            'Oyunun dili ile Ayarlar › Çeviri\'deki kaynak dil aynı mı?',
            'Is the game\'s language the same as the source language in Settings › Translation?',
          ),
          L.t(
            '"TV\'ye deneme altyazısı gönder" çalışıyorsa TV bağlantısı sağlamdır; sorun okumadadır.',
            'If "Send test subtitle to TV" works, the TV connection is fine; the problem is in the reading.',
          ),
        ]),
        _Qa(L.t('Çeviri yarım ya da anlamsız', 'Translation is partial or makes no sense'), [
          L.t('Cümlenin başı ya da sonu eksikse bölgeyi genişlet.', 'If the start or end of a sentence is missing, widen the area.'),
          L.t('Motor "Cihazda" ise Google ya da DeepL\'e geç.', 'If the engine is "On device", switch to Google or DeepL.'),
          L.t(
            'Çok süslü ya da çok küçük yazı tiplerinde okuma zorlaşır; oyunda altyazı boyutunu büyütmek ve arka plan eklemek yardımcı olur.',
            'Reading gets harder with very ornate or very small fonts; increasing the subtitle size in the game and adding a background helps.',
          ),
        ]),
        _Qa(L.t('Çeviri geç geliyor', 'Translation arrives late'), [
          L.t(
            'Telefon ve PS5 mümkünse modeme yakın olsun; zayıf Wi-Fi görüntüyü geciktirir.',
            'Keep the phone and PS5 close to the router if possible; weak Wi-Fi delays the picture.',
          ),
          L.t('Çevrimiçi motorlarda internet hızı da etkiler.', 'With online engines, internet speed matters too.'),
        ]),
        _Qa(L.t('Ekranı kapatınca çeviri duruyor', 'Translation stops when the screen turns off'), [
          L.t(
            'Telefonun pil tasarrufu uygulamayı durduruyor olabilir. Telefonun Ayarlar › Uygulamalar › GameTranslator › Pil bölümünden "Kısıtlanmamış"ı seç.',
            'The phone\'s battery saver may be stopping the app. In the phone\'s Settings › Apps › GameTranslator › Battery, choose "Unrestricted".',
          ),
          L.t(
            'Bildirim iznini kapattıysan aç; arka plan servisi bildirimle çalışır.',
            'If you turned off notification permission, turn it back on; the background service runs with a notification.',
          ),
        ]),
        _Tip(L.t(
          'Çözemediğin bir sorun olursa Ayarlar › Hakkında › Günlük\'teki kayıtları kopyalayıp paylaşabilirsin.',
          'If you cannot solve a problem, you can copy the records in Settings › About › Log and share them.',
        )),
      ],
    ),
  ];
}

/// Paragraf.
class _P extends StatelessWidget {
  const _P(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: const TextStyle(color: Tokens.textSecondary, fontSize: 15.5, height: 1.45, letterSpacing: -0.2)),
      );
}

/// Bölüm içi ara başlık.
class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(text, style: Txt.headline),
      );
}

/// Numaralı adımlar.
class _Steps extends StatelessWidget {
  const _Steps(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Tokens.accentSoft, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(color: Tokens.accentText, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.1)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(items[i], style: const TextStyle(fontSize: 15.5, height: 1.42, letterSpacing: -0.2)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sırasız liste.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 9, right: 12),
                    child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Tokens.accentText, shape: BoxShape.circle)),
                  ),
                  Expanded(child: Text(item, style: const TextStyle(color: Tokens.textSecondary, fontSize: 15.5, height: 1.42, letterSpacing: -0.2))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// İpucu kutusu.
class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Notice(icon: CupertinoIcons.lightbulb_fill, text: text),
      );
}

/// Ad ve açıklama çiftleri: kumanda tuşları, çeviri motorları.
class _Keys extends StatelessWidget {
  const _Keys(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (final (name, text) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 104,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.inset,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Tokens.border),
                    ),
                    child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(text, style: const TextStyle(color: Tokens.textSecondary, fontSize: 14, height: 1.4)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Desteklenen TV'ler: marka, ayrıntı ve destek durumu.
class _Table extends StatelessWidget {
  const _Table(this.rows);

  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(color: Tokens.inset, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tokens.border, width: 0.8)),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      rows[i].$3 ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                      size: 20,
                      color: rows[i].$3 ? Tokens.success : Tokens.danger,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(rows[i].$2, style: const TextStyle(color: Tokens.textSecondary, fontSize: 13.5, height: 1.35)),
                          if (!rows[i].$3)
                            Text(L.t('Desteklenmiyor: bu TV\'lere uygulama kurulamıyor.', 'Not supported: the app cannot be installed on these TVs.'), style: const TextStyle(color: Tokens.danger, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sorun ve denenecekler.
class _Qa extends StatelessWidget {
  const _Qa(this.question, this.answers);

  final String question;
  final List<String> answers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(CupertinoIcons.question_circle_fill, size: 18, color: Tokens.warning),
              ),
              Expanded(child: Text(question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35))),
            ],
          ),
          _Bullets(answers),
        ],
      ),
    );
  }
}

/// TV uygulaması eski bir adrese (ör. kapalı bilgisayara) takılı kaldığında yapılacaklar. Sorun gidermede ve
/// ana ekrandaki uyarıdan açılan sayfada aynı metin kullanılır.
List<Widget> get tvRecoverySteps => [
      _P(L.t(
        'TV uygulaması en son bağlandığı adresi hatırlar. Daha önce bilgisayara bağlandıysa, telefonu aramak yerine o '
            'adresi denemeye devam edebilir. Kayıtlı adresi silince uygulama ağı baştan tarar ve telefonu bulur.',
        'The TV app remembers the last address it connected to. If it was connected to a computer before, it may keep trying that '
            'address instead of looking for the phone. Once you clear the saved address, the app scans the network again and finds the phone.',
      )),
      const _Sub('Android TV / Google TV (TCL, Sony, Philips, Vestel…)'),
      _Steps([
        L.t(
          'TV\'de Ayarlar › Uygulamalar\'a gir ve listeden GameTranslator\'ı seç ("Tüm uygulamaları göster" gerekebilir).',
          'On the TV go to Settings › Apps and pick GameTranslator from the list ("See all apps" may be needed).',
        ),
        L.t(
          '"Verileri temizle"yi seç ve onayla. Uygulama silinmez, yalnızca kayıtlı adres ve ayarlar sıfırlanır.',
          'Choose "Clear data" and confirm. The app is not removed; only the saved address and settings are reset.',
        ),
        L.t(
          'Telefonda çeviri açıkken TV\'de GameTranslator\'ı yeniden aç.',
          'With translation on, reopen GameTranslator on the TV.',
        ),
        L.t(
          'Bir dakikaya kadar bekle; telefondaki TV karosu "Bağlı" olur.',
          'Wait up to a minute; the TV tile on the phone shows "Connected".',
        ),
      ]),
      _Sub(L.t('Samsung ve LG', 'Samsung and LG')),
      _Steps([
        L.t(
          'Bu TV\'lerde uygulama verisi ayrı silinemez: GameTranslator\'ı TV\'den kaldır.',
          'On these TVs the app data cannot be cleared separately: remove GameTranslator from the TV.',
        ),
        L.t(
          'Bilgisayardaki GameTranslator ile yeniden kur ("TV\'yi hazırla" bölümündeki adımlar).',
          'Install it again with GameTranslator on the computer (the steps in the "Prepare the TV" section).',
        ),
        L.t(
          'Bilgisayardaki GameTranslator\'ı kapat, telefonda çeviriyi başlat ve TV\'de uygulamayı aç.',
          'Close GameTranslator on the computer, start the translation on the phone and open the app on the TV.',
        ),
      ]),
      _Sub(L.t('Yine olmazsa', 'If it still does not work')),
      _Bullets([
        L.t(
          'Bilgisayardaki GameTranslator kapalı mı? Açıksa TV ona bağlanır.',
          'Is GameTranslator on the computer closed? If it is open, the TV connects to it.',
        ),
        L.t(
          'Telefon ve TV aynı Wi-Fi ağında mı? Modemde "istemci yalıtımı" (AP isolation) açıksa cihazlar birbirini göremez.',
          'Are the phone and TV on the same Wi-Fi network? If "client isolation" (AP isolation) is on in the router, devices cannot see each other.',
        ),
        L.t(
          'TV\'de HDMI ayarı da sıfırlandığı için Tamam ile paneli açıp PS5\'in girişini yeniden seç.',
          'The HDMI setting on the TV is reset as well, so open the panel with OK and choose the PS5\'s input again.',
        ),
      ]),
    ];

/// Ana ekrandaki "TV hâlâ bağlanmadı" uyarısından açılan yardım sayfası.
class TvHelpPage extends StatelessWidget {
  const TvHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: L.t('TV Bağlanmıyor', 'TV Won\'t Connect'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Glass(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tvRecoverySteps),
          ),
        ],
      ),
    );
  }
}

/// Rehberdeki "TV uygulamasını kur" düğmesi: telefondan kurulum sihirbazını açar.
class InstallTvButton extends StatelessWidget {
  const InstallTvButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GlowButton(
          icon: CupertinoIcons.tv_fill,
          label: L.t('TV uygulamasını kur', 'Install the TV app'),
          onPressed: () => Navigator.of(context).push(appleRoute<void>((_) => const TvInstallPage())),
        ),
      );
}
