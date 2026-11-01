extends RefCounted
## Turkish text for every English string in the game. The English text is the key:
## labels and buttons in main.tscn are translated automatically, and main.gd passes
## its messages through tr(). Add a line here whenever new text is added.

const TURKISH := {
	# Main menu
	"FILL THE BOARD. MATCH THE COUNTS.": "TAHTAYI DOLDUR. SAYILARI TUTTUR.",
	"CLASSIC": "KLASİK",
	"LEVEL %d": "SEVİYE %d",
	"TIME ATTACK": "ZAMANA KARŞI",
	"%d S START  /  +%d S PER REGION": "%d SN BAŞLANGIÇ  /  BÖLGE BAŞINA +%d SN",
	"BEST %d": "REKOR %d",
	"MULTIPLAYER": "ÇOK OYUNCULU",
	"PLAY WITH A FRIEND NEARBY": "YAKINDAKİ ARKADAŞINLA OYNA",
	"COMING SOON": "YAKINDA",
	"SETTINGS": "AYARLAR",
	# Settings
	"SOUND": "SES",
	"MUSIC": "MÜZİK",
	"VIBRATION": "TİTREŞİM",
	"LANGUAGE": "DİL",
	"ON": "AÇIK",
	"OFF": "KAPALI",
	"HOW TO PLAY": "NASIL OYNANIR",
	"CLOSE": "KAPAT",
	# How to play
	"1. Drag pieces from the tray to fill every square of the 9 x 9 board.": "1. Alttaki parçaları sürükleyerek 9 x 9 tahtanın tüm karelerini doldur.",
	"2. Each 3 x 3 region shows how many different pieces must touch it.": "2. Her 3 x 3 bölgedeki sayı, o bölgeye kaç farklı parçanın değmesi gerektiğini gösterir.",
	"3. Tap the rotate icon under a piece to turn it 90 degrees.": "3. Parçayı 90 derece çevirmek için altındaki döndür simgesine dokun.",
	"4. Classic: finish the board to reach the next level. Time Attack: you start with 45 seconds, every completed region adds 20 seconds and is replaced by a new one.": "4. Klasik: tahtayı bitir, sonraki seviyeye geç. Zamana Karşı: 45 saniyeyle başlarsın, tamamlanan her bölge 20 saniye ekler ve yerine yeni bir bölge gelir.",
	"Too many pieces in a region, a region reaching its count before it is full, or no piece fitting anywhere ends the game.": "Bir bölgeye fazla parça değerse, bölge dolmadan sayısına ulaşırsa ya da hiçbir parça sığmazsa oyun biter.",
	"GOT IT": "ANLADIM",
	# Game screen
	"LEVEL %d  /  TARGETS 3-%d": "SEVİYE %d  /  HEDEFLER 3-%d",
	"TIME ATTACK  /  BEST %d": "ZAMANA KARŞI  /  REKOR %d",
	"COMBO x%d": "KOMBO x%d",
	"RESET": "SIFIRLA",
	"TAP ROTATE / DRAG TO PLACE": "DOKUN ÇEVİR / SÜRÜKLE YERLEŞTİR",
	"Fill the board and make every region count match.": "Tahtayı doldur ve her bölgenin sayısını tuttur.",
	"Complete regions to win more time.": "Bölgeleri tamamlayarak süre kazan.",
	"Puzzle reset. Try a new arrangement.": "Bulmaca sıfırlandı. Yeni bir dizilim dene.",
	"That piece does not fit there.": "Bu parça oraya sığmıyor.",
	"+%d points  /  Combo x%d": "+%d puan  /  Kombo x%d",
	"  /  +%d s": "  /  +%d sn",
	"No available piece can fit on the board.": "Elindeki parçaların hiçbiri tahtaya sığmıyor.",
	"Board full, but some region counts do not match.": "Tahta doldu ama bazı bölgelerin sayısı tutmuyor.",
	"Puzzle complete! Every region is satisfied.": "Bulmaca tamam! Bütün bölgeler tuttu.",
	"Too many pieces touch a region.": "Bir bölgeye fazla parça değiyor.",
	"A region reached its target before all squares were filled.": "Bir bölge, tüm kareleri dolmadan hedefine ulaştı.",
	"A full region does not have enough pieces.": "Dolu bir bölgede yeterli parça yok.",
	"Time is up.": "Süre doldu.",
	# Windows
	"PAUSED": "DURAKLATILDI",
	"RESUME": "DEVAM ET",
	"NEW PUZZLE": "YENİ BULMACA",
	"MAIN MENU": "ANA MENÜ",
	"GAME FAILED": "OYUN BİTTİ",
	"Back to level 1.": "1. seviyeye dönüyorsun.",
	"RESTART": "YENİDEN BAŞLA",
	"TIME'S UP": "SÜRE DOLDU",
	"RUN OVER": "OYUN BİTTİ",
	"Score: %d  /  Best: %d": "Skor: %d  /  Rekor: %d",
	"New record!": "Yeni rekor!",
	"LEVEL COMPLETE": "SEVİYE TAMAM",
	"The next puzzle will be a little harder.": "Sonraki bulmaca biraz daha zor olacak.",
	"NEXT LEVEL": "SONRAKİ SEVİYE",
}

static var _registered := false

## Adds the Turkish translation to the TranslationServer once.
static func register() -> void:
	if _registered:
		return
	_registered = true
	var turkish := Translation.new()
	turkish.locale = "tr"
	for english in TURKISH:
		turkish.add_message(english, TURKISH[english])
	TranslationServer.add_translation(turkish)
