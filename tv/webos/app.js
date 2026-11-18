// SPDX-License-Identifier: AGPL-3.0-only
// GameTranslator TV uygulaması (webOS ve Tizen ortak).
// HDMI girişini tam ekran gösterir, üstüne GameTranslator uygulamasından gelen altyazıyı basar.
// TV'ye özgü işler platform.js'tedir. Eski TV tarayıcıları için ES5 ile yazıldı.
//
// Altyazı olayı (SSE `event: subtitle`), TV'nin okuduğu alanlar:
//   text      Çeviri. Birden çok konuşmacı satır sonuyla ayrılır ("Ad: metin\nAd2: metin2"); etiketsiz devam satırı
//             da kendi satırındadır. İki ya da daha çok dolu satır varsa her satır ayrı kutuda, alt alta ve ortalı
//             çizilir (1.0.8'den beri). Boş satırlar atlanır.
//   duration  Gösterim süresi (ms).
//   box       Oyundaki altyazının yeri, ekrana oranla 0–1: {"left","top","right","bottom"}. Yoksa sabit yükseklik.
//   source    Örtmede çevirinin sığdırılacağı gerçek yazı alanı (box ile aynı biçim). İsteğe bağlı.
//   line      Oyundaki satır yüksekliği, ekran yüksekliğine oranla (0–1). İsteğe bağlı.
//   rows      İsteğe bağlı (1.0.8): her satırın oyundaki yeri, örtme (cover) yerleşimi için.
//             "rows":[{"box":{"left":..,"top":..,"right":..,"bottom":..},"line":0.034}, ...]
//             Sıra ve sayı text.split("\n") ile birebir aynıdır (boş satırlar da sayılır; göndermemek en iyisi).
//             box zorunlu, line isteğe bağlıdır (o satırın yazı boyu için üst sınır; yoksa üstteki line).
//             Yalnız örtme yerleşiminde, üst düzeyde box da varken kullanılır: her satır kendi kutusunu opak
//             zeminle örter. Sayı tutmazsa ya da bir kutu geçersizse rows yok sayılır ve birleşik box/source
//             kullanılır. Eski TV sürümleri bu alanı tanımaz; eski telefon sürümleri göndermez.
// Ping olayı (SSE `event: ping`, `data: {}`): sunucu bağlantı açıkken 15 sn'de bir yollar. Yorum satırı (": ping")
//   EventSource'a olay olarak gelmez, TV yalnız adlandırılmış olayı görür. TV bir bağlantıda en az bir ping gördükten
//   sonra veri nöbetçisini açar: o bağlantıda 40 sn hiçbir olay (ping, altyazı, stil, clear…) gelmezse bağlantı
//   yarı açık sayılır, kapatılır ve aynı adrese hemen yeniden bağlanılır. Ping yollamayan eski sunucularda nöbetçi
//   hiç açılmaz (sessizlik bağlantıyı koparmaz).
// GET /hello yanıtı: gövdede küçük harfle "gametranslator" geçmeli. "active" alanı çevirinin çalışıp çalışmadığını
//   söyler: {"active":true,"app":"gametranslator"} ya da {"active":false,"app":"gametranslator"}.
//   - true: çeviri yapıyor. Taramada bulunduğu an ona bağlanılır.
//   - false: açık ama çeviri yapmıyor. Bağlı sunucu 30 sn altyazısız kalıp false derse TV ağda true diyen başka
//     sunucu arar ve bulursa ona geçer (bağlantı yine kopmaz).
//   - alan yok: eski sunucu, durum bilinmiyor. Bağlantı korunur, boşta tarama yapılmaz.
//   Kopunca TV önce kayıtlı adresi tek /hello ile yoklar; yanıt gelirse (active ne olursa olsun) hemen bağlanır.
(function () {
  'use strict';

  // TV uygulamasının sürümü: appinfo.json, tv-tizen/config.xml ve tv-android/app/build.gradle ile aynı tutulur.
  var APP_VERSION = '1.0.8';
  var t = window.t;
  var config = window.GAMETRANSLATOR_CONFIG || window.GAMETRANSLATOR_CONFIG || {};
  var platform = window.GAMETRANSLATOR_PLATFORM || window.GAMETRANSLATOR_PLATFORM;
  var KEY = { RED: 403, GREEN: 404, BLUE: 406, LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, OK: 13, BACK: platform.backKey };

  var server = null;
  var eventSource = null;
  // Kumandayla seçilen port kayıtlıysa o kullanılır, yoksa PS5 otomatik aranır.
  var savedPort = Number(load('hdmi'));
  var hdmiPort = savedPort || 1;

  var bottomPercent = 7;
  // Çevirinin yeri: oyundaki İngilizce altyazının üstünü örterek (cover), üstünde (above), altında (below)
  // ya da sabit yükseklikte (fixed). Yeri bildirmeyen eski GameTranslator sürümlerinde sabit kalır.
  var PLACEMENTS = { cover: 1, above: 1, below: 1, fixed: 1 };
  var placement = 'fixed';
  // Gösterilen satırın oyundaki İngilizce altyazının yeri (ekrana oranla), bilinmiyorsa null.
  var currentBox = null;
  // Oyunun altyazısının gerçek yeri (örtme yerleşiminde çeviri buraya sığdırılır), ayarlardaki yazı boyu ve
  // yazının şu an sığdırılmış olup olmadığı.
  var currentSource = null;
  var baseFontSize = 0;
  var fitted = false;
  // Oyunun altyazısının satır yüksekliği (ekran yüksekliğine oranla); bilinmiyorsa 0.
  var currentLine = 0;
  var coverBackground = '';
  // Konuşmacı adının rengi; boşsa ad ayrı renkte yazılmaz.
  var speakerColor = '';
  // Gösterilen yazı birden çok satırlıysa satırları ({text, index}); tek satırlıysa null.
  var textRows = null;
  // Satırların oyundaki yerleri ({text, box, line}); telefon göndermediyse ya da satırlarla uyuşmuyorsa null.
  var currentRows = null;

  // Önceki satır bu süreden kısa göründüyse okunamamış olabilir; yeni satırın üstünde bir süre daha kalır.
  var PREVIOUS_HOLD_MS = 2500;
  var shownAt = 0;
  var previousTimer = null;

  var hideTimer = null;
  var panelTimer = null;

  // Bilgisayarın "temizle" olayı satırı bundan erken kaldırmaz: oyundaki satır çeviri gelirken kalkmışsa yazı TV'de
  // bir an görünüp kayboluyordu. Süre, bilgisayarın okuma süresi kuralıyla aynıdır; üst sınırı daha kısadır.
  var HOLD_MAX_MS = 5000;
  var holdUntil = 0;
  // Bağlantı bir an koptuğunda yazı silinmez; ancak bu süre içinde geri gelmezse silinir.
  var DROP_HIDE_MS = 6000;
  var dropTimer = null;

  // Panelde görünen tanı bilgisi: "yazı TV'ye gelmiyor" bildirimlerinde sebebi buradan okuruz.
  var diag = { subtitles: 0, clears: 0, drops: 0, backgrounded: 0, lastHide: '-', place: '-', error: '', stale: 0 };

  function $(id) { return document.getElementById(id); }

  function renderDiag() {
    var el = $('st-diag');
    if (!el) return;
    el.textContent = 'sub ' + diag.subtitles + ' · clear ' + diag.clears + ' · drop ' + diag.drops +
      ' · bg ' + diag.backgrounded + ' · hide ' + diag.lastHide + ' · ' + diag.place +
      (window.__screenSaverStatus ? ' · saver ' + window.__screenSaverStatus : '') +
      (diag.error ? ' · err ' + diag.error : '') + connectionDiag();
  }

  // Bağlantının tanısı: yeniden bağlanma sayısı, son verinin yaşı, nöbetçi açık mı, sunucunun "active" durumu.
  function connectionDiag() {
    var age = lastDataAt && eventSource ? Math.round((Date.now() - lastDataAt) / 1000) + 's' : '-';
    var active = serverActive === true ? 'true' : serverActive === false ? 'false' : '?';
    return ' · rc ' + reconnects + ' (stale ' + diag.stale + ') · data ' + age + ' · wd ' + (sawPing ? 'on' : 'off') +
      ' · act ' + active;
  }

  function noteError(message) {
    diag.error = String(message).slice(0, 120);
    renderDiag();
  }

  window.onerror = function (message, source, line) {
    noteError(message + ' @' + line);
    return false;
  };

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) diag.backgrounded++;
    // Askıdan dönüş: bağlantı askıda ölmüş olabilir; son veri eskiyse beklemeden yeniden bağlanılır.
    else onResume();
    renderDiag();
  });

  function load(key) {
    try { return window.localStorage.getItem('gametranslator.' + key) || window.localStorage.getItem('gametranslator.' + key); } catch (e) { return null; }
  }

  function save(key, value) {
    try { window.localStorage.setItem('gametranslator.' + key, String(value)); } catch (e) {}
  }

  function setStatus(id, text, cls) {
    var el = $(id);
    el.textContent = text;
    el.className = cls || '';
  }

  // --- Başlatma parametreleri ---

  function parseParams(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try {
      return JSON.parse(raw) || {};
    } catch (e) {
      try {
        var unescaped = raw.replace(/\\"/g, '"');
        return JSON.parse(unescaped) || {};
      } catch (e2) {
        var m = /"server"\s*:\s*"([^"]+)"/.exec(raw) || /server[:=]\s*(\S+)/.exec(raw);
        if (m) return { server: m[1] };
        return {};
      }
    }
  }

  // Parametrelerdeki sunucu ve HDMI tercihini uygular; sunucu değiştiyse ya da aynı sunucuya bağlı değilsek yeniden
  // bağlanır.
  function applyParams(params) {
    if (params.hdmi >= 1 && params.hdmi <= 4) {
      hdmiPort = Number(params.hdmi);
      save('hdmi', hdmiPort);
      showHdmi(hdmiPort);
    }
    if (params.server && (params.server !== server || !isOpen())) {
      save('server', params.server);
      connect(params.server);
    }
  }

  // --- HDMI görüntüsü ---

  function showHdmi(port) {
    setStatus('st-hdmi', String(port));
    var statuses = {
      loading: ['loading', 'muted'],
      ready: ['videoReady', 'ok'],
      playing: ['playing', 'ok'],
      inputError: ['inputError', 'bad'],
      sourceError: ['sourceError', 'bad']
    };
    platform.showHdmi(port, $('video-host'), function (kind) {
      setStatus('st-video', t(statuses[kind][0]), statuses[kind][1]);
    });
  }

  function autoSelectConsole(onNotFound) {
    platform.findConsolePort(function (port, label) {
      if (!port) return onNotFound && onNotFound();
      if (port !== hdmiPort) {
        hdmiPort = port;
        showHdmi(port);
      }
      setStatus('st-hdmi', port + ' — ' + label + ' (' + t('auto') + ')');
    });
  }

  // --- Altyazı ---

  // Kutunun sayıları geçerli mi (0–1 arası, sağ soldan, alt üstten büyük).
  function validBox(box) {
    if (!box || typeof box !== 'object') return null;
    var left = Number(box.left), top = Number(box.top), right = Number(box.right), bottom = Number(box.bottom);
    if (isNaN(left) || isNaN(top) || isNaN(right) || isNaN(bottom)) return null;
    left = Math.max(0, Math.min(0.98, left));
    right = Math.max(left + 0.01, Math.min(1.0, right));
    top = Math.max(0, Math.min(0.98, top));
    bottom = Math.max(top + 0.01, Math.min(1.0, bottom));
    return { left: left, top: top, right: right, bottom: bottom };
  }

  // paragraphs: görev paneli gibi başlık ve maddeli yazılar satır satır, sola yaslı gösterilir.
  function showSubtitle(text, duration, box, paragraphs, source, line, rows) {
    // source: oyunun altyazısının gerçek yeri (örtme yerleşiminde çeviri tam bu alana sığdırılır).
    currentSource = paragraphs ? null : validBox(source);
    currentLine = typeof line === 'number' && line > 0 ? line : 0;
    // Önceki satır artık ayrıca gösterilmez: iki kutu üst üste binmiş gibi görünüyor, aynı cümlenin iki okunuşu
    // da ikinci çeviri gibi duruyordu. Yeni satır eskisinin yerine geçer.
    hidePrevious();
    shownAt = Date.now();
    holdUntil = shownAt + Math.min(HOLD_MAX_MS, 2000 + text.length * 60);
    currentBox = validBox(box);
    var split = paragraphs ? null : splitRows(text);
    textRows = split && split.rows.length > 1 ? split.rows : null;
    currentRows = textRows ? validRows(rows, split.count, textRows) : null;
    if (textRows) {
      setRowsText($('subtitle-text'), textRows);
    } else {
      $('subtitle-text').className = '';
      setSubtitleText($('subtitle-text'), text, paragraphs);
    }
    $('subtitle-text').style.whiteSpace = paragraphs ? 'pre-line' : '';
    // Maddeli yazılar satır başına yaslanır: soldan sağa dillerde sola, sağdan sola dillerde sağa
    $('subtitle-text').style.textAlign = paragraphs ? (isRtl(text) ? 'right' : 'left') : '';
    $('subtitle').className = '';
    layout();
    setStatus('st-last', text.length > 40 ? text.slice(0, 40) + '…' : text);
    notePlace();
    clearTimeout(hideTimer);
    // Geçersiz ya da çok kısa süre yazıyı gösterir göstermez kaldırmasın.
    var ms = duration > 0 ? Math.max(1000, duration) : Math.min(8000, 2000 + text.length * 60);
    hideTimer = setTimeout(function () { hideSubtitle('timer'); }, ms);
  }

  // Konuşmacı adları ("MARKOS: …", cümle ortasında başlayan ikinci konuşmacı dahil) ayarlarda açıksa ayrı renkte
  // yazılır. Ad büyük harfle başlayan en çok üç sözcüktür ve satır başında ya da bir cümlenin bitiminde durur.
  var SPEAKER = /(^|[.!?…”"]\s+|\n)([A-ZÇĞİÖŞÜÂÎÛ][^\s:.!?]*(?: [A-ZÇĞİÖŞÜÂÎÛ][^\s:.!?]*){0,2}):(?=\s)/g;
  // Metin sağdan sola mı okunur (Arapça, Farsça, İbranice): harflerin çoğunluğuna bakılır; satır "MARKOS:" gibi Latin bir
  // adla başlasa da Arapça söz sağdan sola dizilir. Bilgisayardaki Languages.IsRtlText ve ikinci ekran sayfasıyla aynı kural.
  function isRtl(text) {
    var rtl = (text.match(/[֐-ࣿיִ-﷿ﹰ-﻿]/g) || []).length;
    if (!rtl) return false;
    var letters = (text.match(/[A-Za-zÀ-ɏͰ-ԯ぀-ヿ一-鿿가-힯]/g) || []).length;
    return rtl >= letters;
  }

  function setSubtitleText(el, text, paragraphs) {
    el.dir = isRtl(text) ? 'rtl' : 'ltr';
    if (!speakerColor || paragraphs) {
      el.textContent = text;
      return;
    }
    el.textContent = '';
    var last = 0, match;
    SPEAKER.lastIndex = 0;
    while ((match = SPEAKER.exec(text)) !== null) {
      var nameStart = match.index + match[1].length;
      if (nameStart > last) el.appendChild(document.createTextNode(text.slice(last, nameStart)));
      var name = document.createElement('span');
      name.style.color = speakerColor;
      name.textContent = match[2] + ':';
      el.appendChild(name);
      last = SPEAKER.lastIndex;
    }
    if (last < text.length) el.appendChild(document.createTextNode(text.slice(last)));
  }

  // Yazının dolu satırları (index: satırın text.split("\n") içindeki yeri) ve toplam satır sayısı.
  function splitRows(text) {
    var parts = String(text).split(/\r?\n/);
    var rows = [];
    for (var i = 0; i < parts.length; i++) {
      var row = parts[i].trim();
      if (row) rows.push({ text: row, index: i });
    }
    return { rows: rows, count: parts.length };
  }

  // Satır kutusu validBox'tan sıkıdır: eksik değer ya da ters kutu (sol ≥ sağ, üst ≥ alt) düzeltilmez, reddedilir.
  // Tek kutu yolu (validBox) eskisi gibi kalır.
  function rowBox(box) {
    if (!box || typeof box !== 'object') return null;
    var values = [box.left, box.top, box.right, box.bottom];
    for (var i = 0; i < values.length; i++) {
      if (values[i] === null || values[i] === undefined || values[i] === '' || isNaN(Number(values[i]))) return null;
    }
    if (Number(box.left) >= Number(box.right) || Number(box.top) >= Number(box.bottom)) return null;
    return validBox(box);
  }

  // Telefonun gönderdiği satır yerleri: sayısı satır sayısını tutmuyorsa ya da bir kutu geçersizse hiç kullanılmaz.
  function validRows(list, count, rows) {
    if (!list || Object.prototype.toString.call(list) !== '[object Array]' || list.length !== count) return null;
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var item = list[rows[i].index];
      var box = rowBox(item && item.box);
      if (!box) return null;
      var line = Number(item.line);
      out.push({ text: rows[i].text, box: box, line: line > 0 && line < 1 ? line : 0 });
    }
    return out;
  }

  // Birden çok satır: her satır (konuşmacı) kendi kutusunda, alt alta; kutu satırın yazısı kadar geniştir.
  function setRowsText(el, rows) {
    el.textContent = '';
    el.className = 'rows';
    // Yön her satırda ayrıca seçilir (setSubtitleText); kap tüm yazının yönünü alır.
    var all = [];
    for (var j = 0; j < rows.length; j++) all.push(rows[j].text);
    el.dir = isRtl(all.join(' ')) ? 'rtl' : 'ltr';
    for (var i = 0; i < rows.length; i++) {
      var line = document.createElement('div');
      line.className = 'row-line';
      var row = document.createElement('span');
      row.className = 'row';
      setSubtitleText(row, rows[i].text, false);
      line.appendChild(row);
      el.appendChild(line);
    }
  }

  // Satır kutularının zemini yazının zemin ayarını izler (ayar yazı ekrandayken de değişebilir).
  function paintRows() {
    if (!textRows) return;
    var el = $('subtitle-text');
    var lines = el.childNodes;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].firstChild) lines[i].firstChild.style.background = el.style.background;
    }
  }

  // Yazının ekrandaki gerçek yeri ve görünürlüğü (tanı için).
  function notePlace() {
    var el = $('subtitle-text');
    var rect = el.getBoundingClientRect();
    var height = document.documentElement.clientHeight || window.innerHeight || 0;
    diag.place = 'y ' + Math.round(rect.top) + '-' + Math.round(rect.bottom) + '/' + height + ' ' +
      window.getComputedStyle($('subtitle')).visibility + ' f' + window.getComputedStyle(el).fontSize +
      (textRows ? ' rows ' + textRows.length + ($('subtitle').style.visibility === 'hidden' ? ' placed' : '') : '');
    renderDiag();
  }

  // reason: yazıyı neyin kaldırdığı; panelde görünen süreyle birlikte sebebi gösterir.
  function hideSubtitle(reason) {
    clearTimeout(hideTimer);
    if ($('subtitle').className !== 'hidden') {
      diag.lastHide = (reason || '?') + ' ' + (Date.now() - shownAt) + 'ms';
      renderDiag();
    }
    $('subtitle').className = 'hidden';
    $('subtitle-cover').className = 'hidden';
    hideRowCovers();
    hidePrevious();
  }

  // Bilgisayardan gelen "temizle": yazı okunacak kadar görünmediyse kalan süre dolunca kaldırılır.
  function onClear() {
    diag.clears++;
    renderDiag();
    var left = holdUntil - Date.now();
    if (left <= 0 || $('subtitle').className === 'hidden') return hideSubtitle('clear');
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function () { hideSubtitle('clear-held'); }, left);
  }

  function showPrevious(text) {
    $('subtitle-prev-text').textContent = text;
    $('subtitle-prev').className = '';
    clearTimeout(previousTimer);
    previousTimer = setTimeout(hidePrevious, PREVIOUS_HOLD_MS);
  }

  function hidePrevious() {
    clearTimeout(previousTimer);
    $('subtitle-prev').className = 'hidden';
  }

  // --- Ekranı çevir ---
  // Bilgisayar ekranın tamamını okuyup her yazı grubunun çevirisini yeriyle gönderir. Her çeviri kendi İngilizce
  // yazısını örter; yazı boyu o yazının satır yüksekliğinden seçilir, Türkçe uzun gelirse sığana kadar küçülür.

  var screenTimer = null;
  var SCREEN_PAD = 0.004;
  var SCREEN_MIN_FONT = 14;

  function showScreen(items, duration) {
    var host = $('screen');
    // "Ekran çevriliyor…" yazısı sonuçların üstünde kalmasın.
    hideSubtitle('screen');
    host.innerHTML = '';
    host.className = '';
    var width = window.innerWidth || 1920;
    var height = window.innerHeight || 1080;
    for (var i = 0; i < (items || []).length; i++) {
      var item = items[i];
      var box = validBox(item && item.box);
      if (!box || !item.text) continue;
      var el = document.createElement('div');
      el.className = item.paragraphs === true ? 'item paragraphs' : 'item';
      el.textContent = item.text;
      var left = Math.max(0, box.left - SCREEN_PAD);
      var top = Math.max(0, box.top - SCREEN_PAD);
      var boxHeight = (box.bottom - box.top + 2 * SCREEN_PAD) * height;
      el.style.left = (left * 100) + '%';
      el.style.top = (top * 100) + '%';
      el.style.width = Math.max(80, (Math.min(1, box.right + SCREEN_PAD) - left) * width) + 'px';
      el.style.minHeight = Math.round(boxHeight) + 'px';
      var line = typeof item.line === 'number' && item.line > 0 ? item.line * height : box.bottom * height - box.top * height;
      var size = Math.max(SCREEN_MIN_FONT, Math.min(96, Math.round(line * 0.95)));
      el.style.fontSize = size + 'px';
      host.appendChild(el);
      // Türkçe çoğu zaman İngilizceden uzundur: kutu biraz uzayabilir, daha fazlası için yazı küçülür.
      var limit = Math.max(boxHeight * 1.5, line * 2.6);
      while (el.scrollHeight > limit && size > SCREEN_MIN_FONT) {
        size -= 2;
        el.style.fontSize = size + 'px';
      }
    }
    clearTimeout(screenTimer);
    screenTimer = setTimeout(hideScreen, duration || 20000);
  }

  function hideScreen() {
    clearTimeout(screenTimer);
    $('screen').className = 'hidden';
    $('screen').innerHTML = '';
  }

  // Konum hem GameTranslator uygulamasından hem kumandanın oklarıyla ayarlanır. Kumandayla
  // seçilen konum, uygulamadaki ayar değişene kadar korunur (son değiştiren geçerlidir).
  function setBottom(percent) {
    bottomPercent = Math.max(0, Math.min(85, percent));
    layout();
  }

  // Altyazıyı seçilen yerleşime göre konumlar. İngilizce altyazının yeri bilinmiyorsa sabit yükseklik kullanılır.
  function layout() {
    var el = $('subtitle');
    var cover = $('subtitle-cover');
    var box = placement === 'fixed' ? null : currentBox;

    el.style.left = '4%';
    el.style.right = '4%';
    el.style.top = 'auto';
    el.style.bottom = Math.max(2, Math.min(88, bottomPercent)) + '%';
    el.style.transform = 'none';
    el.style.webkitTransform = 'none';
    cover.className = 'hidden';
    unfit();
    restoreRowsSize();
    hideRowCovers();
    paintRows();

    // Altyazı yokken veya kutu tanımlı değilken örtü tek başına kalmasın
    if (!box || el.className === 'hidden') {
      keepRowsOnScreen();
      return;
    }

    var mode = placement;
    // Ekranın kenarında yer yoksa öbür yana geçilir.
    if (mode === 'below' && box.bottom > 0.88) mode = 'above';
    if (mode === 'above' && box.top < 0.12) mode = 'below';

    if (mode === 'cover' && currentRows && $('subtitle-rows')) {
      showRowCovers(currentRows);
    } else if (mode === 'cover' && currentSource) {
      fitToSource(el, cover, currentSource);
    } else if (mode === 'cover') {
      // İngilizce altyazının tam üstünü örten koyu zemin
      var padX = 0.02; // Yatayda %2 pay
      var padY = 0.015; // Dikeyde %1.5 pay
      var cLeft = Math.max(0.01, box.left - padX);
      var cTop = Math.max(0.01, box.top - padY);
      var cRight = Math.min(0.99, box.right + padX);
      var cBottom = Math.min(0.99, box.bottom + padY);

      cover.style.left = (cLeft * 100).toFixed(2) + '%';
      cover.style.top = (cTop * 100).toFixed(2) + '%';
      cover.style.width = ((cRight - cLeft) * 100).toFixed(2) + '%';
      cover.style.height = ((cBottom - cTop) * 100).toFixed(2) + '%';
      cover.className = '';

      // Türkçe çeviri bu örtünün tam ortasına dikeyde oturur
      var centerBottom = (1.0 - (box.top + box.bottom) / 2.0) * 100.0;
      el.style.top = 'auto';
      el.style.bottom = Math.max(2, Math.min(92, centerBottom)).toFixed(2) + '%';
      el.style.transform = 'translateY(50%)';
      el.style.webkitTransform = 'translateY(50%)';
    } else if (mode === 'above') {
      // İngilizce yazının hemen üstünde (İngilizce yazıyı kapatmaz)
      cover.className = 'hidden';
      var aboveBottom = (1.0 - box.top) * 100.0 + 1.5;
      el.style.top = 'auto';
      el.style.bottom = Math.max(5, Math.min(94, aboveBottom)).toFixed(2) + '%';
      el.style.transform = 'none';
      el.style.webkitTransform = 'none';
    } else if (mode === 'below') {
      // İngilizce yazının hemen altında
      cover.className = 'hidden';
      var belowTop = box.bottom * 100.0 + 1.5;
      el.style.bottom = 'auto';
      el.style.top = Math.max(5, Math.min(94, belowTop)).toFixed(2) + '%';
      el.style.transform = 'none';
      el.style.webkitTransform = 'none';
    }
    keepRowsOnScreen();
  }

  // Çok satır ekrana sığmıyorsa (üstten ya da alttan taşıyor) yazı ayarlardaki boyun 0,6 katına kadar küçülür.
  // Yalnız alt alta kutularda; tek satırlı yazıya ve sığdırma yerleşimlerine dokunmaz.
  var rowsShrunk = false;
  function keepRowsOnScreen() {
    var el = $('subtitle');
    if (!textRows || fitted || el.className === 'hidden' || el.style.visibility === 'hidden') return;
    var text = $('subtitle-text');
    var height = window.innerHeight || document.documentElement.clientHeight || 1080;
    var base = baseFontSize || 46;
    var min = Math.round(base * 0.6);
    var size = base;
    var rect = text.getBoundingClientRect();
    while ((rect.top < 0 || rect.bottom > height) && size > min) {
      size = Math.max(min, size - 2);
      text.style.fontSize = size + 'px';
      rowsShrunk = true;
      rect = text.getBoundingClientRect();
    }
  }

  function restoreRowsSize() {
    if (!rowsShrunk) return;
    rowsShrunk = false;
    $('subtitle-text').style.fontSize = baseFontSize ? baseFontSize + 'px' : '';
  }

  // Çeviriyi oyunun altyazısının kapladığı alana sığdırır: aynı genişlikte sarılır, yazı boyu alana sığan en büyük
  // boydur (ayarlardaki boyun 0,6–1,6 katı arasında). Böylece çeviri oyunun altyazısıyla aynı yerde, aynı satır
  // düzeninde ve hemen hemen aynı boyda durur; zemin tek parçadır. En küçük boyda da sığmıyorsa zemin yazıya göre büyür.
  function fitToSource(el, cover, box) {
    var padded = padBox(box);
    var left = padded.left, right = padded.right, top = padded.top, bottom = padded.bottom;
    // Zemin önce oyunun altyazısının yerine konur; ölçüler ondan alınır (yüzde ve piksel karışmasın).
    var place = function (l, t, r, b) {
      cover.style.left = (l * 100).toFixed(3) + '%';
      cover.style.top = (t * 100).toFixed(3) + '%';
      cover.style.width = ((r - l) * 100).toFixed(3) + '%';
      cover.style.height = ((b - t) * 100).toFixed(3) + '%';
    };
    place(left, top, right, bottom);
    // Oyunun altyazısı alttan hiç görünmesin: zemin tam opaktır.
    if (!fitted) coverBackground = cover.style.background;
    cover.style.background = 'rgb(10, 10, 12)';
    cover.className = '';
    var area = cover.getBoundingClientRect();
    var perX = area.width / (right - left), perY = area.height / (bottom - top);

    var text = $('subtitle-text');
    el.style.left = (left * 100).toFixed(3) + '%';
    el.style.right = ((1 - right) * 100).toFixed(3) + '%';
    el.style.bottom = 'auto';
    el.style.top = (((top + bottom) / 2) * 100).toFixed(3) + '%';
    el.style.transform = 'translateY(-50%)';
    el.style.webkitTransform = 'translateY(-50%)';
    text.style.padding = '0 6px';
    text.style.lineHeight = '1.2';
    // Birden çok satır: satır kutuları da sığdırmadaki dar boşluğu alır.
    if (textRows) text.className = 'rows fit';

    text.style.fontSize = fitSize(text, area, perY, currentLine) + 'px';

    // Yazı en küçük boyda da taşıyorsa zemin onu da içine alacak kadar büyür (tek parça kalır).
    var rect = text.getBoundingClientRect();
    var growTop = Math.max(0, area.top - rect.top + 2) / perY, growBottom = Math.max(0, rect.bottom - area.bottom + 2) / perY;
    var growLeft = Math.max(0, area.left - rect.left + 2) / perX, growRight = Math.max(0, rect.right - area.right + 2) / perX;
    if (growTop || growBottom || growLeft || growRight)
      place(Math.max(0, left - growLeft), Math.max(0, top - growTop), Math.min(1, right + growRight), Math.min(1, bottom + growBottom));
    fitted = true;
  }

  // Oyunun yazı alanına küçük bir pay; çok dar altyazıda (tek sözcük) çeviri en az minWidth kadar yer bulur.
  function padBox(box) {
    var padX = 0.008, padY = 0.006;
    var left = Math.max(0, box.left - padX), right = Math.min(1, box.right + padX);
    var top = Math.max(0, box.top - padY), bottom = Math.min(1, box.bottom + padY);
    var minWidth = 0.16;
    if (right - left < minWidth) {
      var center = (left + right) / 2;
      left = Math.max(0, center - minWidth / 2);
      right = Math.min(1, center + minWidth / 2);
    }
    return { left: left, top: top, right: right, bottom: bottom };
  }

  // Yazının alana (piksel) sığan en büyük boyu. En büyük boy oyunun altyazısının boyudur (satır yüksekliği line
  // biliniyorsa); bilinmiyorsa ayarlardaki boy.
  function fitSize(text, area, perY, line) {
    var base = baseFontSize || 46;
    var low = Math.max(16, Math.round(base * 0.55));
    var high = line > 0 ? Math.round(line * perY * 1.05) : Math.round(base * 1.15);
    high = Math.max(low, Math.min(Math.round(base * 1.6), high));
    var fits = function (size) {
      text.style.fontSize = size + 'px';
      var rect = text.getBoundingClientRect();
      return rect.width <= area.width + 1 && rect.height <= area.height + 1;
    };
    var best = low;
    if (fits(high)) best = high;
    else if (fits(low)) {
      var a = low, b = high;
      while (b - a > 1) {
        var mid = Math.floor((a + b) / 2);
        if (fits(mid)) a = mid; else b = mid;
      }
      best = a;
    }
    return best;
  }

  function setRect(el, l, t, r, b) {
    el.style.left = (l * 100).toFixed(3) + '%';
    el.style.top = (t * 100).toFixed(3) + '%';
    el.style.width = ((r - l) * 100).toFixed(3) + '%';
    el.style.height = ((b - t) * 100).toFixed(3) + '%';
  }

  // Satırların oyundaki yerleri biliniyorsa (örtme): her satır kendi İngilizce satırının üstünü opak zeminle örter ve
  // o satıra sığdırılır (fitToSource'un satır başına karşılığı). Birleşik yazı bu sırada gizlenir.
  function showRowCovers(rows) {
    var host = $('subtitle-rows');
    var source = $('subtitle-text');
    host.innerHTML = '';
    host.className = '';
    $('subtitle').style.visibility = 'hidden';
    // Önce bütün örtüler, sonra bütün yazılar eklenir: bir satırın opak örtüsü komşu satırın taşan yazısını kapatmasın
    // (aynı katmanda sonra eklenen üstte çizilir).
    var covers = [];
    var i;
    for (i = 0; i < rows.length; i++) {
      var padded = padBox(rows[i].box);
      var block = document.createElement('div');
      block.className = 'row-cover';
      setRect(block, padded.left, padded.top, padded.right, padded.bottom);
      host.appendChild(block);
      covers.push({ el: block, box: padded });
    }
    for (i = 0; i < rows.length; i++) {
      var r = covers[i].box;
      var cover = covers[i].el;
      var area = cover.getBoundingClientRect();
      var perX = area.width / (r.right - r.left), perY = area.height / (r.bottom - r.top);

      var place = document.createElement('div');
      place.className = 'row-place';
      place.style.left = (r.left * 100).toFixed(3) + '%';
      place.style.right = ((1 - r.right) * 100).toFixed(3) + '%';
      place.style.top = (((r.top + r.bottom) / 2) * 100).toFixed(3) + '%';
      var text = document.createElement('span');
      text.className = 'row';
      // Yazı rengi, kalınlığı ve zemini ayarlardan (birleşik yazıya verilmiş olan) gelir.
      text.style.color = source.style.color;
      text.style.fontWeight = source.style.fontWeight;
      text.style.background = source.style.background;
      setSubtitleText(text, rows[i].text, false);
      place.appendChild(text);
      host.appendChild(place);
      text.style.fontSize = fitSize(text, area, perY, rows[i].line || currentLine) + 'px';

      // En küçük boyda da taşıyorsa zemin yazıyı içine alacak kadar büyür.
      var rect = text.getBoundingClientRect();
      var growTop = Math.max(0, area.top - rect.top + 2) / perY, growBottom = Math.max(0, rect.bottom - area.bottom + 2) / perY;
      var growLeft = Math.max(0, area.left - rect.left + 2) / perX, growRight = Math.max(0, rect.right - area.right + 2) / perX;
      if (growTop || growBottom || growLeft || growRight)
        setRect(cover, Math.max(0, r.left - growLeft), Math.max(0, r.top - growTop), Math.min(1, r.right + growRight), Math.min(1, r.bottom + growBottom));
    }
  }

  function hideRowCovers() {
    $('subtitle').style.visibility = '';
    var host = $('subtitle-rows');
    if (!host) return;
    host.className = 'hidden';
    host.innerHTML = '';
  }

  // Sığdırma yerleşiminden çıkınca yazının ayarlardaki boyu ve boşlukları geri gelir.
  function unfit() {
    if (!fitted) return;
    fitted = false;
    var text = $('subtitle-text');
    $('subtitle-cover').style.background = coverBackground;
    text.style.padding = '';
    text.style.lineHeight = '';
    if (textRows) text.className = 'rows';
    if (baseFontSize) text.style.fontSize = baseFontSize + 'px';
  }

  // Bazı TV'lerde sabit konumun ekran dışına taşmasını engeller.
  function keepOnScreen(el, cover) {
    if (placement === 'fixed') {
      bottomPercent = Math.max(2, Math.min(85, bottomPercent));
      el.style.bottom = bottomPercent + '%';
    }
  }

  function applyStyle(style) {
    if (style.fontSize) {
      baseFontSize = style.fontSize;
      $('subtitle-text').style.fontSize = style.fontSize + 'px';
      $('subtitle-prev-text').style.fontSize = Math.round(style.fontSize * 0.8) + 'px';
    }
    if (style.color) {
      $('subtitle-text').style.color = style.color;
      $('subtitle-prev-text').style.color = style.color;
    }
    if (PLACEMENTS[style.placement]) placement = style.placement;
    if (typeof style.speakerColor === 'string') speakerColor = style.speakerColor;
    if (typeof style.background === 'number') {
      var alpha = Math.max(0, Math.min(100, style.background)) / 100;
      $('subtitle-text').style.background = 'rgba(0, 0, 0, ' + alpha + ')';
      $('subtitle-prev-text').style.background = 'rgba(0, 0, 0, ' + (alpha * 0.83).toFixed(2) + ')';
      var coverEl = $('subtitle-cover');
      // Örtü İngilizce altyazıyı tamamen kapatmalı: %92 koyulukta beyaz yazı soluk da olsa seçiliyordu.
      if (coverEl) coverEl.style.background = 'rgb(10, 10, 12)';
    }
    if (typeof style.bold === 'boolean') {
      $('subtitle-text').style.fontWeight = style.bold ? '700' : '600';
      $('subtitle-prev-text').style.fontWeight = style.bold ? '700' : '600';
    }
    if (style.bottomPercent >= 0) {
      bottomPercent = Math.max(0, Math.min(92, Number(style.bottomPercent)));
    }
    layout();
  }

  function nudgeSubtitle(step) {
    // Yer oyundaki altyazıya bağlıysa kumandayla taşınmaz.
    if (placement !== 'fixed') return;
    setBottom(bottomPercent + step);
    save('bottom', bottomPercent);
    // Nereye gittiği görülsün diye yazı yoksa örnek gösterilir.
    if ($('subtitle').className === 'hidden') showSubtitle(t('positionPreview'), 2500);
  }

  // --- Sunucu bağlantısı (Server-Sent Events) ---

  // Bağlantının tek sahibi: aynı anda yalnız bir EventSource vardır. Her connect kuşağı (connGen) artırır; eski
  // bağlantının geç gelen olayları ve hataları yok sayılır.
  var connGen = 0;
  // Bu bağlantıdan son olayın (ping dahil) geldiği an ve bu bağlantıda ping görülüp görülmediği (nöbetçi).
  var lastDataAt = 0;
  var sawPing = false;
  var STALE_MS = 40000;
  // Tarayıcı EventSource'u kapattıysa (CLOSED) TV aynı adresi kendisi yeniden dener; art arda başarısızlıkta uzar.
  var RETRY_STEPS_MS = [2000, 3000, 5000, 8000, 10000];
  var retryStep = 0;
  var retryTimer = null;
  var reconnects = 0;
  // Bağlanma denemesinin başladığı an (connect ya da tarayıcının her yeniden denemesi); askıda kalan deneme bu
  // süreden sonra yenilenir.
  var attemptAt = 0;
  var CONNECT_TIMEOUT_MS = 10000;

  function onEvent(source, gen, name, handler) {
    source.addEventListener(name, function (e) {
      if (gen !== connGen) return;
      lastDataAt = Date.now();
      if (name === 'ping') {
        sawPing = true;
        return;
      }
      var data;
      try {
        data = JSON.parse(e.data);
      } catch (err) {
        noteError(name + ': bad json');
        return;
      }
      try {
        handler(data);
      } catch (err) {
        noteError(name + ': ' + err.message);
      }
    });
  }

  // Eski bağlantı kapatılır; olayları kuşak denetimiyle zaten yok sayılır, işleyiciler de bırakılır.
  function closeSource() {
    connGen++;
    if (!eventSource) return;
    eventSource.onopen = null;
    eventSource.onerror = null;
    try { eventSource.close(); } catch (e) { /* yok */ }
    eventSource = null;
  }

  function connect(address) {
    if (demoRunning()) stopDemo(true);
    closeSource();
    clearTimeout(retryTimer);
    retryTimer = null;
    if (address !== server) {
      failures = 0;
      retryStep = 0;
    }
    // Sunucunun "active" durumu her bağlantıda yeniden öğrenilir (undefined: henüz sorulmadı).
    serverActive = undefined;
    idleScanAt = 0;
    idleScanPause = IDLE_RESCAN_MS;
    lastSubtitleAt = Date.now();
    lastDataAt = Date.now();
    attemptAt = Date.now();
    sawPing = false;
    server = address;
    $('waiting').className = 'hidden';
    setStatus('st-server', address);
    if (!window.EventSource) {
      setStatus('st-conn', t('noEventSource'), 'bad');
      return;
    }
    setStatus('st-conn', t('connecting'), 'muted');
    var gen = connGen;
    var source;
    try {
      source = new EventSource(address + '/events');
    } catch (e) {
      // Adres bozuksa ya da motor reddederse yine yeniden denenir ve ağ taranır.
      setStatus('st-conn', t('reconnecting'), 'bad');
      scheduleRetry();
      noteFailure();
      return;
    }
    eventSource = source;
    source.onopen = function () {
      if (gen !== connGen) return;
      failures = 0;
      retryStep = 0;
      resetScanPause();
      lastDataAt = Date.now();
      // Bağlandık: süren ya da bekleyen tarama bırakılır, geç dönen yanıtları yok sayılır.
      cancelScan();
      stopScan();
      clearTimeout(dropTimer);
      dropTimer = null;
      setStatus('st-conn', t('connected'), 'ok');
      renderDiag();
    };
    source.onerror = function () {
      if (gen !== connGen) return;
      attemptAt = Date.now();
      // Bağlantı kısa süre içinde geri gelmezse eski altyazı ekranda asılı kalmasın. Bir anlık kopma yazıyı silmez.
      diag.drops++;
      renderDiag();
      if (dropTimer === null) {
        dropTimer = setTimeout(function () {
          dropTimer = null;
          hideSubtitle('drop');
          hideScreen();
        }, DROP_HIDE_MS);
      }
      setStatus('st-conn', t('reconnecting'), 'bad');
      // Tarayıcı vazgeçtiyse (CLOSED) aynı adres TV tarafından yeniden denenir; yeniden deniyorsa (CONNECTING) ona
      // bırakılır, ikinci bağlantı açılmaz.
      if (source.readyState === 2) scheduleRetry();
      // Bilgisayarın adresi değişmiş olabilir.
      noteFailure();
    };
    onEvent(source, gen, 'ping', null);
    onEvent(source, gen, 'subtitle', function (data) {
      diag.subtitles++;
      lastSubtitleAt = Date.now();
      idleScanAt = 0;
      idleScanPause = IDLE_RESCAN_MS;
      renderDiag();
      if (data.text) showSubtitle(data.text, data.duration, data.box, data.paragraphs === true, data.source, data.line, data.rows);
    });
    onEvent(source, gen, 'clear', onClear);
    onEvent(source, gen, 'screen', function (data) { showScreen(data.items, data.duration); });
    onEvent(source, gen, 'screen-clear', hideScreen);
    onEvent(source, gen, 'style', applyStyle);
    onEvent(source, gen, 'speech', function (data) { if (data.url) playSpeech(server + data.url); });
    onEvent(source, gen, 'speech-stop', stopSpeech);
  }

  function scheduleRetry() {
    if (retryTimer !== null || !server) return;
    var delay = RETRY_STEPS_MS[Math.min(retryStep, RETRY_STEPS_MS.length - 1)];
    retryStep++;
    retryTimer = setTimeout(function () {
      retryTimer = null;
      reconnectNow();
    }, delay);
  }

  // Demo sürerken yeniden bağlanılmaz (connect demoyu kapatırdı); demo bitince bağlantı yoksa yeniden bağlanılır.
  function reconnectNow() {
    if (!server || demoRunning()) return;
    reconnects++;
    connect(server);
    renderDiag();
  }

  // Nöbetçi açıkken (bu bağlantıda ping görüldü) 40 sn hiç veri gelmediyse bağlantı bayatlamıştır.
  function isStale() {
    return sawPing && Date.now() - lastDataAt >= STALE_MS;
  }

  // Askıda zamanlayıcılar durur, nöbetçi çalışamaz: dönüşte bir ping aralığından uzun süredir veri yoksa bağlantı ölü
  // sayılır (ping yollamayan eski sunucuda da tek bir yeniden bağlanma zararsızdır).
  var RESUME_STALE_MS = 20000;
  function onResume() {
    resetScanPause();
    if (!server || demoRunning()) return;
    if (!isOpen() || Date.now() - lastDataAt >= RESUME_STALE_MS) reconnectNow();
  }

  // Saniyede bir: veri nöbetçisi, boşta sunucu denetimi ve panel açıksa tanı satırı. Tek zamanlayıcıdır, hiç kapanmaz.
  var HEARTBEAT_MS = 1000;
  function heartbeat() {
    // Demo sürerken yeniden bağlanılmaz (demo bitince yapılır); bayat sayacı da boşuna artmasın.
    if (demoRunning()) {
      if ($('panel').className !== 'hidden') renderDiag();
      return;
    }
    if (eventSource && isStale()) {
      // Yarı açık bağlantı: tarayıcı açık sanıyor ama sunucudan 40 sn hiçbir şey gelmedi. Hata olayı gelmediği için
      // tarama da buradan planlanır (yeni bağlantı açılırsa iptal edilir).
      diag.stale++;
      noteFailure();
      reconnectNow();
    } else if (eventSource && eventSource.readyState === 0 && Date.now() - attemptAt >= CONNECT_TIMEOUT_MS) {
      // Bağlanma denemesi ne açıldı ne hata verdi (yanıtsız adres): yeni denemeyle değiştirilir. Kapatılan deneme
      // hata vermeyeceği için tarama buradan planlanır; yoksa yanıtsız kayıtlı adreste TV sonsuza dek beklerdi.
      noteFailure();
      reconnectNow();
    } else {
      checkIdle();
    }
    if ($('panel').className !== 'hidden') renderDiag();
  }

  // --- Türkçe dublaj ---
  // Bilgisayar her cümleyi seslendirip adresini gönderir; TV oyunun sesiyle birlikte çalar. Bilgisayar sıradakini
  // bu ses bitince gönderir; yine de üst üste gelirse eskisi kesilir.

  var speech = null;

  function playSpeech(url) {
    stopSpeech();
    try {
      speech = new Audio(url);
      var played = speech.play();
      if (played && played.catch) played.catch(function () { speech = null; });
    } catch (e) {
      speech = null;
    }
  }

  function stopSpeech() {
    if (!speech) return;
    try { speech.pause(); } catch (e) { /* yok */ }
    speech = null;
  }

  // --- Bilgisayarı ağda bulma ---
  // Bilgisayar TV uygulamasını açamıyorsa adres gelmez; kayıtlı adres de eskiyebilir (bilgisayarın IP'si değişti).
  // Uygulama o zaman ağı tarar: TV'nin kendi ağını (adresini söyleyebiliyorsa) ve kayıtlı adresin ağını. Kopmadan
  // SCAN_FIRST_MS sonra kayıtlı adres yoklanır, yanıt yoksa ağ taranır. LG webOS'ta platform.localAddress yoktu; tarama
  // hiç başlamıyor, TV eski adreste sonsuza dek bekliyordu.

  var SERVER_PORT = 8787;
  var SCAN_PARALLEL = 24;
  var SCAN_TIMEOUT_MS = 1200;
  // Bağlantı kopunca ilk tarama bu kadar sonra (önce doğrudan yeniden bağlanma şansı). Sonuçsuz taramadan sonra
  // bekleme uzar: 25 → 50 → 100 → en çok 120 sn; bağlanınca, uygulama öne gelince ya da kumandada bir tuşa basılınca
  // sıfırlanır. Kayıtlı adrese doğrudan yeniden bağlanma (en çok 10 sn arayla) bundan bağımsız sürer. Bağlıyken
  // tarama yalnız boşta sunucu denetiminden başlar.
  var SCAN_FIRST_MS = 6000;
  var SCAN_PAUSE_MS = 25000;
  var SCAN_PAUSE_MAX_MS = 120000;
  var scanPause = SCAN_PAUSE_MS;
  var scanTimer = null;
  var scanDue = 0;
  var nextScanAt = 0;
  var scanning = false;
  // Her tarama kuşağı (scanGen) artırır; bırakılan taramanın geç dönen yanıtları yok sayılır, istekleri kesilir.
  var scanGen = 0;
  var scanRequests = [];
  var failures = 0;
  // Ağda birden çok GameTranslator olabilir (bilgisayardaki uygulama açık dururken telefonla çeviri): TV ilk bulduğuna
  // bağlanıp altyazısız kalıyordu. Sunucu /hello yanıtında "active" (çeviri çalışıyor) bildirir; bağlı sunucu 30 sn
  // altyazısız kalıp "active":false derse ağ taranır, çeviri yapan başka sunucuya geçilir. Alanı hiç göndermeyen
  // (eski) sunucuda durum bilinmez; bağlantı korunur ve taranmaz.
  var IDLE_RESCAN_MS = 30000;
  // undefined: bu bağlantıda henüz sorulmadı; null: sunucu alanı göndermiyor; true/false: sunucunun yanıtı.
  var serverActive;
  var lastSubtitleAt = 0;
  var idleProbeAt = 0;
  var idleProbing = false;
  // Sonuçsuz boşta taramadan sonra bir sonraki daha geç yapılır (30 → 60 → 120 sn); altyazı ya da yeni bağlantı
  // sıfırlar. İki sunucu da "active":false derken ağ 30 sn'de bir taranmasın.
  var IDLE_SCAN_MAX_MS = 120000;
  var idleScanPause = IDLE_RESCAN_MS;
  var idleScanAt = 0;

  function isOpen() { return !!eventSource && eventSource.readyState === 1; }

  function checkIdle() {
    var now = Date.now();
    if (!isOpen() || scanning || idleProbing || serverActive === null) return;
    if (now - lastSubtitleAt < IDLE_RESCAN_MS || now - idleProbeAt < IDLE_RESCAN_MS) return;
    idleProbeAt = now;
    idleProbing = true;
    var current = server, gen = connGen;
    probe(current, function (ok, active) {
      idleProbing = false;
      if (gen !== connGen) return;
      if (ok) serverActive = active;
      renderDiag();
      if (!(ok && active === false && isOpen()) || Date.now() - idleScanAt < idleScanPause) return;
      // Bir önceki boşta tarama sonuçsuz kaldıysa (hâlâ aynı bağlantıdayız) bekleme uzar.
      if (idleScanAt) idleScanPause = Math.min(IDLE_SCAN_MAX_MS, idleScanPause * 2);
      idleScanAt = Date.now();
      scanForServer();
    });
  }

  // Bekleyen tarama daha erken başlayacaksa korunur; EventSource birkaç saniyede bir yeniden denediği için sayaç
  // baştan kurulursa tarama hiç başlamazdı. Sonuçsuz taramadan sonra bir sonraki SCAN_PAUSE_MS'ten önce başlamaz.
  function scheduleScan(delay) {
    if (scanning) return;
    if (delay === undefined) delay = SCAN_PAUSE_MS;
    var due = Math.max(Date.now() + delay, nextScanAt);
    if (scanTimer !== null && scanDue <= due) return;
    clearTimeout(scanTimer);
    scanDue = due;
    scanTimer = setTimeout(function () {
      scanTimer = null;
      scanForServer();
    }, due - Date.now());
  }

  function cancelScan() {
    clearTimeout(scanTimer);
    scanTimer = null;
  }

  // Tarama beklemesi baştan başlar; kopukken uzak bir zamana kurulmuş tarama öne alınır.
  function resetScanPause() {
    scanPause = SCAN_PAUSE_MS;
    nextScanAt = 0;
    if (scanTimer !== null && !isOpen() && scanDue - Date.now() > SCAN_FIRST_MS) {
      cancelScan();
      scheduleScan(SCAN_FIRST_MS);
    }
  }

  // Süren tarama bırakılır: istekler kesilir, geç dönen yanıtlar kuşak denetimiyle yok sayılır.
  function stopScan() {
    scanGen++;
    scanning = false;
    for (var i = 0; i < scanRequests.length; i++) {
      try { scanRequests[i].abort(); } catch (e) { /* yok */ }
    }
    scanRequests = [];
  }

  // Bağlantı hatası: kayıtlı adres önce doğrudan yeniden denenir; bağlanılamazsa birkaç saniye sonra taranır.
  function noteFailure() {
    failures++;
    scheduleScan(SCAN_FIRST_MS);
  }

  function subnetOf(address) {
    var match = /^(?:https?:\/\/)?(\d+\.\d+\.\d+)\.\d+(?::\d+)?\/?$/.exec(address || '');
    // Bağlı olmayan ağ arabirimi 0.0.0.0 bildirir; kendi kendine atanmış (169.254) ve yerel (127) adresler de taranmaz.
    if (!match || /^(0\.0\.0|127\.|169\.254\.)/.test(match[1] + '.')) return null;
    return match[1];
  }

  // Taranacak ağlar: TV'nin kendi ağı, sonra kayıtlı adresin ağı (aynıysa bir kez); ikisi de yoksa 192.168.1.
  function scanSubnets(done) {
    var fromServer = subnetOf(server || load('server'));
    function finish(ip) {
      var list = [];
      var own = subnetOf(ip);
      if (own) list.push(own);
      if (fromServer && fromServer !== own) list.push(fromServer);
      if (!list.length) list.push('192.168.1');
      done(list);
    }
    if (!platform.localAddress) return finish(null);
    var answered = false;
    var timer = null;
    function once(ip) {
      if (answered) return;
      answered = true;
      clearTimeout(timer);
      finish(ip);
    }
    // Adresi soran servis yanıt vermezse tarama kayıtlı adresin ağıyla sürer.
    timer = setTimeout(function () { once(null); }, 3000);
    try {
      platform.localAddress(once);
    } catch (e) {
      once(null);
    }
  }

  // /hello yanıtındaki "active": true, false ya da alan yoksa null.
  function activeOf(body) {
    var match = /"active"\s*:\s*(true|false)/.exec(body);
    return match ? match[1] === 'true' : null;
  }

  // done(ok, active): active yanıttaki "active" (true/false; alan yoksa ya da yanıt yoksa null). İstek döner (kesmek için).
  function probe(address, done) {
    var request = new XMLHttpRequest();
    var finished = false;
    var guard = null;
    function finish(ok, active) {
      if (finished) return;
      finished = true;
      clearTimeout(guard);
      done(ok, ok && typeof active === 'boolean' ? active : null);
    }
    request.onload = function () {
      var body = (request.responseText || '').toLowerCase();
      finish(request.status === 200 && (body.indexOf('gametranslator') >= 0 || body.indexOf('gametrans') >= 0 || body.indexOf('couchsubs') >= 0),
        activeOf(body));
    };
    request.onerror = function () { finish(false); };
    request.ontimeout = function () { finish(false); };
    // timeout özelliğini tanımayan eski motorlarda da istek bu kadar sonra bırakılır.
    guard = setTimeout(function () {
      try { request.abort(); } catch (e) { /* yok */ }
      finish(false);
    }, SCAN_TIMEOUT_MS + 500);
    try {
      request.open('GET', address + '/hello');
      request.timeout = SCAN_TIMEOUT_MS;
      request.send();
    } catch (e) {
      finish(false);
    }
    return request;
  }

  // Bulunan sunucuya bağlanılır ve adresi kaydedilir (TV bir sonraki açılışta eski adrese takılmasın). Zaten açık
  // bağlantı varsa dokunulmaz; tarayıcı yeniden deniyorsa yerine hemen yeni bağlantı kurulur (bekleme süresi atlanır).
  function useServer(address, active) {
    save('server', address);
    if (address !== server || !isOpen()) connect(address);
    serverActive = active;
    renderDiag();
  }

  // Önce kayıtlı adres tek /hello ile yoklanır: yanıt verirse (active ne olursa olsun) hemen bağlanılır, taranmaz.
  // Bağlıyken (boşta sunucu "active":false dedi) bu adım atlanır; tarama yalnız çeviri yapan sunucuyu arar.
  function scanForServer() {
    if (scanning) return;
    cancelScan();
    stopScan();
    scanning = true;
    var gen = scanGen;
    var saved = server || load('server');
    if (!saved || isOpen()) return fullScan(gen, saved);
    scanRequests.push(probe(saved, function (ok, active) {
      if (gen !== scanGen) return;
      if (!ok) return fullScan(gen, saved);
      stopScan();
      useServer(saved, active);
    }));
  }

  function fullScan(gen, saved) {
    scanSubnets(function (subnets) {
      if (gen !== scanGen) return;
      var addresses = [];
      for (var s = 0; s < subnets.length; s++) {
        for (var host = 1; host <= 254; host++) addresses.push('http://' + subnets[s] + '.' + host + ':' + SERVER_PORT);
      }
      var next = 0, pending = 0, fallback = null;
      function pump() {
        while (pending < SCAN_PARALLEL && next < addresses.length) {
          pending++;
          tryAddress(addresses[next++]);
        }
        if (!pending && next >= addresses.length) {
          stopScan();
          // Çeviri yapan yok: bağlı değilsek bulunan (bekleyen) sunucuya bağlanılır; o da yoksa bir süre sonra yeniden.
          if (fallback && !isOpen()) return useServer(fallback, false);
          if (!isOpen()) {
            nextScanAt = Date.now() + scanPause;
            scanPause = Math.min(SCAN_PAUSE_MAX_MS, scanPause * 2);
            scheduleScan();
          }
        }
      }
      function tryAddress(address) {
        scanRequests.push(probe(address, function (ok, active) {
          if (gen !== scanGen) return;
          pending--;
          if (!ok) return pump();
          // Çeviri yapan sunucu ya da (bağlı değilken) kayıtlı sunucu bulunduğu an bağlanılır, tarama bitmez beklenmez.
          if (active === true || (address === saved && !isOpen())) {
            stopScan();
            return useServer(address, active);
          }
          // Çeviri yapmayan sunucu (ör. açık duran bilgisayar uygulaması) yedekte bekler; tarama çeviri yapanı arar.
          if (!fallback) fallback = address;
          pump();
        }));
      }
      pump();
    });
  }

  // --- Demo ---
  // Mağaza incelemesi ve ilk kez açanlar için: PS5 ve bilgisayar olmadan örnek altyazılar gösterilir.

  var DEMO_LINES = [
    'Buraya ayıracak vaktimiz yok.',
    'MİRA: Kapı daha fazla dayanmayacak!\nKAAN: O zaman arka taraftan çıkıyoruz.',
    'Yakın dur. İlerideki yol tehlikeli.',
    'Bekle! Sen de kimsin?',
    'Bu iş henüz bitmedi.'
  ];
  var DEMO_LINE_MS = 3200;
  var DEMO_GAP_MS = 700;
  var demoTimer = null;
  var demoIndex = 0;

  function demoRunning() { return demoTimer !== null; }

  function nextDemoLine() {
    showSubtitle(DEMO_LINES[demoIndex], DEMO_LINE_MS);
    demoIndex = (demoIndex + 1) % DEMO_LINES.length;
    demoTimer = setTimeout(nextDemoLine, DEMO_LINE_MS + DEMO_GAP_MS);
  }

  function startDemo() {
    if (demoRunning()) return;
    hidePanel();
    $('waiting').className = 'hidden';
    $('demo-badge').className = '';
    demoIndex = 0;
    nextDemoLine();
  }

  // connecting: demoyu connect kapatıyor (yeniden bağlanma tetiklenmez).
  function stopDemo(connecting) {
    clearTimeout(demoTimer);
    demoTimer = null;
    hideSubtitle('demo');
    $('demo-badge').className = 'hidden';
    // Uygulamaya bağlı değilse bekleme ekranına dönülür.
    if (!server) $('waiting').className = '';
    // Demo sırasında ertelenen yeniden bağlanma.
    else if (!connecting && !isOpen()) reconnectNow();
  }

  // Geri tuşu: önce demo ya da panel kapanır; giriş ekranında TV'nin ana ekranına dönülür.
  function goBack() {
    if (demoRunning()) return stopDemo();
    if ($('panel').className !== 'hidden') return hidePanel();
    platform.exit();
  }

  // --- Panel ve kumanda ---

  // "1–4: HDMI girişi · 0: …" satırını tuş başına bir satıra böler; tuş adı vurgu renginde.
  function formatKeys() {
    var el = $('keys');
    var parts = el.textContent.split(' · ');
    el.innerHTML = '';
    for (var i = 0; i < parts.length; i++) {
      var colon = parts[i].indexOf(':');
      var row = document.createElement('div');
      row.className = 'key';
      var key = document.createElement('b');
      key.textContent = colon > 0 ? parts[i].slice(0, colon) : '';
      row.appendChild(key);
      row.appendChild(document.createTextNode(colon > 0 ? parts[i].slice(colon + 1).trim() : parts[i]));
      el.appendChild(row);
    }
  }

  // Panel açıkken bekleme kutusu kapanır: ikisi üst üste binince yazılar okunmuyor.
  function showPanel(autoHide) {
    $('waiting').className = 'hidden';
    $('panel').className = '';
    clearTimeout(panelTimer);
    if (autoHide) panelTimer = setTimeout(hidePanel, 8000);
  }

  function hidePanel() {
    $('panel').className = 'hidden';
    if (!server && !demoRunning()) $('waiting').className = '';
  }

  function togglePanel() {
    if ($('panel').className === 'hidden') showPanel(false); else hidePanel();
  }

  // Sayı tuşu olmayan kumandalar için: panel açıkken sol ve sağ HDMI girişini değiştirir.
  function stepHdmi(step) {
    hdmiPort = (hdmiPort + step + 3) % 4 + 1;
    save('hdmi', hdmiPort);
    showHdmi(hdmiPort);
    showPanel(true);
  }

  document.addEventListener('keydown', function (e) {
    var code = e.keyCode;
    // Kullanıcı TV'nin başında: kopuksa ağ yeniden sık taranır.
    resetScanPause();
    if (code === 48) { // 0: elle seçimi unut, konsolu yeniden ara
      save('hdmi', '');
      autoSelectConsole(function () {
        setStatus('st-hdmi', hdmiPort + ' (' + t('consoleNotFound') + ')', 'bad');
      });
      showPanel(true);
    } else if (code >= 49 && code <= 52) { // 1–4
      hdmiPort = code - 48;
      save('hdmi', hdmiPort);
      showHdmi(hdmiPort);
      showPanel(true);
    } else if (code === KEY.RED) {
      showSubtitle(t('localTest'), 4000);
    } else if (code === KEY.GREEN) {
      togglePanel();
    } else if (code === KEY.BLUE) {
      if (demoRunning()) stopDemo(); else startDemo();
    } else if (code === KEY.OK && $('waiting').className !== 'hidden') {
      startDemo();
    } else if (code === KEY.OK && !demoRunning()) {
      togglePanel();
    } else if ((code === KEY.LEFT || code === KEY.RIGHT) && $('panel').className !== 'hidden') {
      stepHdmi(code === KEY.RIGHT ? 1 : -1);
    } else if (code === KEY.BACK) {
      goBack();
      e.preventDefault();
    } else if (code === KEY.UP || code === KEY.DOWN) {
      nudgeSubtitle(code === KEY.UP ? 3 : -3);
      e.preventDefault();
    }
  });

  // Uygulama zaten açıkken yeniden başlatılırsa (ör. GameTranslator onu öne getirdiğinde) parametreler burada gelir.
  platform.onRelaunch(function (raw) { applyParams(parseParams(raw)); });

  platform.init();
  window.applyI18n();
  formatKeys();
  var savedBottom = load('bottom') || load('appBottom');
  if (savedBottom) setBottom(Number(savedBottom));
  showHdmi(hdmiPort);
  if (!savedPort) autoSelectConsole();

  $('app-version').textContent = APP_VERSION;
  setInterval(heartbeat, HEARTBEAT_MS);
  renderDiag();
  var initial = parseParams(platform.launchParams());
  var address = initial.server || load('server') || config.server;
  applyParams(initial);
  if (!server) {
    if (address) connect(address); else $('waiting').className = '';
  }
  if (!server) scanForServer();
  // Bekleme ekranı açıksa panel kendiliğinden açılmaz; yeşil tuşla açılabilir.
  if (server) showPanel(true); else hidePanel();
})();
