// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Oyun paketleri: uygulamayla gelenler (paketin içindeki "packs" klasörü, bilgisayar uygulamasıyla aynı .json.gz
/// dosyaları) ve sunucudan inenler (Application Support/packs-remote). Android'deki Engine.packLibrary/store/
/// refreshPacks karşılığı. Kütüphane ilk aramada açılır (~1 sn), uygulama boyunca bellekte kalır.
final class Packs {
  static let shared = Packs()

  private let bundleDir = Bundle.main.url(forResource: "packs", withExtension: nil)
  private let refreshLock = NSLock()
  private var refreshing = false

  lazy var store: PackStore = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let bundleDir = self.bundleDir
    return PackStore(directory: support.appendingPathComponent("packs-remote"), server: HttpPackServer(PackStore.DEFAULT_URL),
                     bundledHashes: {
                       guard let bundleDir else { return [] }
                       return Set(GamePackLibrary.files(in: bundleDir).compactMap { try? PackStore.sha256($0.read()) })
                     })
  }()

  lazy var library: GamePackLibrary = {
    let bundleDir = self.bundleDir
    // Topluluk yamaları (GitLab patches/) en son okunur: aynı oyunun gömülü paketinin yerine geçer.
    return GamePackLibrary(bundled: { bundleDir.map { GamePackLibrary.files(in: $0) } ?? [] }, userDirectory: store.folder,
                           extraDirectories: [CommunityPatches.shared.folder])
  }()

  /// Haftada bir sunucudaki yeni ve güncellenen paketleri indirir (SHA-256 doğrulanır; uygulamada olanlar inmez).
  /// Arka planda; değişiklik olduysa kütüphane yeniden yüklenir.
  func refresh(log: @escaping (Int, String) -> Void) {
    refreshLock.lock()
    if refreshing { refreshLock.unlock(); return }
    refreshing = true
    refreshLock.unlock()
    DispatchQueue.global(qos: .utility).async {
      defer { self.refreshLock.lock(); self.refreshing = false; self.refreshLock.unlock() }
      do {
        let result = try self.store.refresh()
        if !result.skipped { log(2, "paket sunucusu: \(result.downloaded.count) indirildi, \(result.removed.count) kaldırıldı") }
        if !result.downloaded.isEmpty || !result.removed.isEmpty { self.library.reload() }
      } catch {
        log(1, "paket sunucusuna ulaşılamadı: \(error)")
      }
      // Topluluk yamaları: haftada bir kendiliğinden.
      if let result = try? CommunityPatches.shared.update(force: false, log: log), result.changed { self.library.reload() }
    }
  }

  /// Ayarlardaki "Topluluk yamalarını güncelle": hemen kontrol eder (bloklar). Kullanıcıya gösterilecek metni döner.
  func updateCommunityPatches(log: @escaping (Int, String) -> Void) -> (Bool, String) {
    do {
      guard let result = try CommunityPatches.shared.update(force: true, log: log) else {
        return (true, Lang.t("Güncelleme zaten sürüyor.", "An update is already in progress."))
      }
      if result.changed { library.reload() }
      var parts: [String] = []
      if !result.added.isEmpty { parts.append(Lang.t("\(result.added.count) yeni", "\(result.added.count) new")) }
      if !result.updated.isEmpty { parts.append(Lang.t("\(result.updated.count) güncellendi", "\(result.updated.count) updated")) }
      if !result.removed.isEmpty { parts.append(Lang.t("\(result.removed.count) kaldırıldı", "\(result.removed.count) removed")) }
      if !result.failed.isEmpty {
        return (false, Lang.t("\(result.failed.count) yama inemedi. İnternet bağlantını kontrol edip yeniden dene.",
                              "\(result.failed.count) patches could not be downloaded. Check your internet connection and try again."))
      }
      return (true, parts.isEmpty ? Lang.t("Yamalar güncel.", "Patches are up to date.")
                                  : Lang.t("Yamalar: ", "Patches: ") + parts.joined(separator: ", ") + ".")
    } catch {
      return (false, Lang.t("Yama listesine ulaşılamadı. İnternet bağlantını kontrol et.", "Could not reach the patch list. Check your internet connection."))
    }
  }
}
