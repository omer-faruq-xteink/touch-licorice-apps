title: Dağ Kulübesi
author: omer-faruq
language: tr
licence: CC BY 4.0
about: Kar, bir kulübe, bir gece ve aşağıya uzun bir yol. Her oyun biraz farklı. Yaklaşık on dakika.
start: firtina
var: sicaklik = 3
var: odun = 0
var: yiyecek = 1
var: gun = 1
var: hava = 0
var: harita = false

== firtina
Kar, hava durumunun söylediğinden çok daha hızlı bastırdı. Saat dörde gelince kendi kayaklarının ucunu bile göremiyorsun.
Sonra beyazlığın içinden karanlık bir kare çıkıyor: bir kulübe.
* Sendeleyerek içeri gir -> kulube

== kulube
~ sicaklik = max(sicaklik, 0)
{sicaklik >= 3: Yeterince sıcaksın.|{sicaklik > 0: Üşüyorsun.|Soğuktan titriyorsun ve duramıyorsun.}}
{gun == 1: İlk gece.|{gun}. gece.} Sobanın yanında odun: {odun}. Kalan yiyecek: {yiyecek}.
* {odun > 0} Sobayı yak ~ odun -= 1; sicaklik += 2 -> ates
* [once] Kulübeyi ara -> arama
* Odun için dışarı çık ~ sicaklik -= 1 -> odunluk
* {yiyecek > 0} Bir şeyler ye ~ yiyecek -= 1; sicaklik += 1 -> yemek
* Sabaha kadar uyu -> gece

== arama
Rafta bir kutu bisküvi, duvarda da iğneyle tutturulmuş, elle çizilmiş bir vadi haritası. Güvenli iniş yolu kırmızı kalemle işaretlenmiş.
~ yiyecek += 2
~ harita = true
-> kulube

== odunluk
~ hava = random(1, 6)
{hava <= 2: Rüzgâr odun yığınını bulana kadar seni iki kez yere seriyor. Parmaklarını hissetmeden iki kütükle dönüyorsun.|Odun yığınını kardan kazıyıp çıkarıyor ve bir kucak odunla dönüyorsun.}
~ odun += 3
~ {hava <= 2} odun -= 1
~ {hava <= 2} sicaklik -= 1
-> kulube

== ates
Soba çıtırdayıp gürlüyor. Askıdaki eldivenlerinden buhar yükseliyor.
-> kulube

== yemek
Biraz yumuşamış bisküviler. Hayatının en güzel yemeği.
-> kulube

== gece
~ sicaklik -= 2
~ hava = random(1, 6)
{sicaklik > 0: Kötü uyuyorsun, ama uyuyorsun.|Bütün gece uyuyamayacak kadar üşüyerek uyanık yatıyorsun.}
-> {sicaklik <= -2} donma
-> sabah

== sabah
~ gun += 1
{hava >= 4: Sabah açık ve dingin. Bütün vadi aşağıda parıl parıl.|Kar hâlâ yağıyor, artık daha yumuşak. Belki elli metre ötesini görebiliyorsun.}
* {hava >= 4} Hemen aşağı kay -> inis
* {hava < 4 and harita} Haritaya bakarak aşağı kay -> inis_harita
* {hava < 4} Yine de aşağı kay -> kaybolma
* {gun < 4} Bir gün daha kal -> kulube
* {gun >= 4} Bir gün daha kal -> kurtarma

== inis
Uzun, yumuşak yamaçları teker teker iniyorsun. Öğlene doğru köyün çatılarını görüyorsun, saat birde de sanki hiçbir şey olmamış gibi kafede sıcak çikolata içiyorsun.
-> END

== inis_harita
Kırmızı kalem çizgisi seni asla bulamayacağın, rüzgârdan korunaklı bir dereye indiriyor. Ağaçların arasında kar diniyor ve köy aşağıda beliriyor.
-> END

== kaybolma
Beyazlığın içinde her yer aynı görünüyor. Bir saat kayıyorsun ve kendi izlerini buluyorsun. Sonra kulübeyi yeniden buluyorsun; bu da bir tür şans.
~ sicaklik -= 1
-> kulube

== kurtarma
Dördüncü gün, görmeden önce duyuyorsun: sırtın üstünden alçaktan uçan bir helikopter. Kafede biri arabanın hâlâ otoparkta durduğunu fark etmiş.
Pilot elini sıkıyor. "Yerinde kalmakla iyi etmişsin," diyor.
-> END

== donma
Şafaktan bir süre önce soğuğu hissetmez oluyorsun, bu da olabilecek en kötü işaret. İki gün sonra seni bulan kurtarma ekibi yaşadığın için şanslı olduğunu söylüyor.
Bir dahaki sefere sobayı söndürme.
-> END
