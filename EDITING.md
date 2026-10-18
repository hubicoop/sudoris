# Sudoris'i Godot'da düzenleme

Proje **Godot 4.7.2** ile açılır:

```
~/AppImages/Godot_v4.7.2-stable_linux.x86_64 --editor --path ~/sudoris-dev
```

`main.tscn` açıldığında tahta ve tepsi editörde örnek parçalarla görünür. Yaptığın değişiklikler anında ekrana yansır. Oyunu çalıştırmak için **F5**.

## Nerede ne var

| Değiştirmek istediğin | Nereden |
|---|---|
| Tahta ve tepsi renkleri, font, sayı etiketleri | `skin/default_skin.tres` → çift tıkla, Inspector'da düzenle |
| Parça karesi görseli | `art/block.png` (beyaz/gri çiz, oyun parçanın rengiyle boyar) |
| Döndür ikonu | `art/rotate.svg` |
| Parıltı görseli | `art/sparkle.png` |
| Boş kare görseli | Skin → Sprites → Empty Cell Texture (şu an boş, düz renk) |
| Sürükleme hissi, kenara yapışma | `BoardView` node'u → Inspector → **Drag** |
| Döndürme animasyonunun süresi | `TrayView` node'u → Inspector → **Rotate Duration** (saniye, 0 = anında döner) |
| Bölge tamamlanma animasyonu | `BoardView` → **Region Clear** |
| Üçlü sıra dalgası | `BoardView` → **Line Wave** |
| Parça renkleri, puanlama, combo süresi | Kök `Sudoris` node'u → Inspector |
| İlk bölüm yardımı (kaç bölgeden sonra, hangi seviyeye kadar, ne sıklıkla) | Kök `Sudoris` node'u → Inspector → **Level Help** |
| Titreşim (açık/kapalı, taş bırakınca süre ve güç, bölge bitince kaç kat) | Kök `Sudoris` node'u → Inspector → **Haptics** |
| Pencerelerin açılış animasyonu | `PauseModal`, `WinModal`, `GameOverModal`, `HowToModal` altındaki `Animator` → Animation panelinde `open` |
| Menü yazıları, butonlar, pencere düzeni | `main.tscn` içindeki node'lar (Label, Button vb.) |
| Oyun kuralları, parça şekilleri, zorluk | `main.gd` → `shape_catalog()`, `maximum_region_target()` |

## Animasyonları elle şekillendirmek

`BoardView` seçiliyken Inspector'daki **Curve** alanlarına tıklayınca eğri editörü açılır:

- **Placement Curve**: bırakılan parçanın yerine kayış şekli (x = zaman, y = alınan yol).
- **Pop Curve**: yeşil bir kareye ulaşınca karenin büyüyüp küçülmesi.
- **Wave Curve**: dalgada her karenin zıplama şekli.

Eğriyi silersen (boş bırakırsan) oyun varsayılan yumuşak hareketi kullanır.

Inspector'ın en altındaki **Preview Region Clear** ve **Preview Line Wave** butonları animasyonu editörün içinde oynatır. Oyunu çalıştırmana gerek kalmaz.

## Kendi görselini eklemek

1. PNG veya SVG dosyasını `art/` klasörüne sürükle.
2. `skin/default_skin.tres` dosyasını aç ve ilgili alana sürükle-bırak yap.

Parça karesi gibi renklendirilen görselleri **beyaz/gri** çiz. Oyun bunları parçanın rengiyle çarparak boyar: beyaz kısımlar tam renk, gri kısımlar koyu görünür.

## Yayınlamak

Değişiklikleri kaydettikten sonra:

```
cd ~/sudoris-dev && git add -A && git commit -m "açıklama" && git push
```

`main`'e her push'ta GitHub Actions ("Web build") Web sürümünü Godot 4.7.2 ile dışa aktarır ve `hubicoop/sudoris` reposunun `gh-pages` dalına yükler. Birkaç dakika sonra https://hubicoop.github.io/sudoris/ güncellenir; elle kopyalamaya gerek yok.

### Tek seferlik kurulum

1. Bir SSH anahtarı üret: `ssh-keygen -t ed25519 -N "" -C sudoris-pages -f sudoris-pages`
2. `hubicoop/sudoris` → Settings → Deploy keys → Add deploy key: `sudoris-pages.pub` içeriğini yapıştır, **Allow write access** kutusunu işaretle.
3. `hubicoop/sudoris-dev` → Settings → Secrets and variables → Actions → New repository secret: adı `SUDORIS_PAGES_DEPLOY_KEY`, değeri `sudoris-pages` (özel anahtar) dosyasının içeriği. Sonra iki anahtar dosyasını da sil.
4. İlk yayından sonra `hubicoop/sudoris` → Settings → Pages → Source: **Deploy from a branch**, dal `gh-pages`, klasör `/ (root)`.
