title: Karanlık Deniz Feneri
author: omer-faruq
language: tr
licence: CC BY 4.0
about: Fırtına, sönmüş bir fener ve kayalıklara doğru gelen bir gemi. Yaklaşık on dakika.
start: iskele
var: adim = 0
var: fener = false
var: kibrit = false
var: anahtar = false
var: gaz = 0
var: bere = 0

== iskele
Seni getiren tekne, daha iki ayağını da iskeleye basmadan yağmurun içinde geri dönüyor. Martı Kayası'nın yeni nöbetçi bekçisisin ve bir gün erken geldin.
Tependeki deniz feneri ışığını denize çeviriyor olmalıydı. Karanlık.
* [once] Denize bak ~ adim += 1 -> deniz
* Bekçi evine çık ~ adim += 1 -> ev
* Doğruca kuleye git ~ adim += 1 -> kule_kapisi

== deniz
Uzakta, güneyde, iki küçük ışık inip kalkıyor: bir gemi, ve bu tarafa geliyor. Gemiyle kaya arasında, fenerin uyarmak için orada durduğu resif var.
Birinin lambayı yakması gerek, hem de hemen.
-> iskele

== ev
{ev == 1: Bekçi evinin kapısı açık, rüzgârda çarpıp duruyor. İçeride ocaktaki ateş gri bir küle dönmüş. Seslendiğinde kimse cevap vermiyor.|Ev önceki kadar soğuk ve boş.}
{fener: Elindeki fener odayı aydınlatıyor.|Kapının yanında bir fırtına feneri asılı, hâlâ ılık.}
* {not fener} Feneri al ~ fener = true -> ev
* [once] Masadaki notu oku -> not_
* [once] Komodinin çekmecelerini ara ~ adim += 1 -> cekmece
* [once] Şömineye bak -> somine
* Kuleye git ~ adim += 1 -> kule_kapisi

== not_
Not iri, özenli bir yazıyla yazılmış:
"Sis çanına bakmaya indim. Altıda dönerim. Tom."
Duvardaki saat onu on geçiyor.
-> ev

== cekmece
İp, mum artıkları, bir kutu düğme. En alt çekmecede, katlanmış bir bayrağın altında, ağır bir demir anahtar.
~ anahtar = true
-> ev

== somine
Beyaz sakallı bir adamla bir köpeğin fotoğrafının arkasında bir kutu kibrit buluyorsun. Sallayınca tıkırdıyor: epey var.
~ kibrit = true
-> ev

== kule_kapisi
Kulenin kapısı demirden, beyaza boyalı ve kilitli.
{anahtar: Çekmeceden aldığın anahtar cebinde ağır ağır duruyor.}
* {anahtar} Kapıyı aç ~ adim += 1 -> merdiven
* {not anahtar} Yanındaki küçük pencereyi kır ~ adim += 2; bere += 1 -> pencere
* Eve geri dön ~ adim += 1 -> ev

== pencere
Cam üçüncü vuruşta kırılıyor, parmak boğumlarının derisi de. Yavaşça, dikkatle içeri tırmanıyorsun.
-> merdiven

== merdiven
{fener: Fener gölgeni duvarlara kocaman yansıtıyor.|Zifiri karanlık. Her basamağı ayağınla yoklayarak çıkıyorsun.}
{not fener: {~Kaval kemiğini korkuluğa çarpıyorsun.|Bir basamağı kaçırıp ellerinin üstüne düşüyorsun.}}
~ {not fener} bere += 1
~ adim += 1
* Lamba odasına çık -> lamba_kontrol
* [once] Depo odasının kapısını dene -> depo
* {bere >= 3} Biraz otur -> dinlen

== dinlen
Soğuk basamağa oturup berelerini sayıyorsun: {bere} tane. Ellerin titriyor. Rüzgâr kulenin etrafında uğulduyor.
~ adim += 2
-> merdiven

== depo
Duvar boyunca gaz yağı varilleri dizili. Kapının yanındaki küçük bidonu dolduruyorsun.
~ gaz = 3
~ adim += 1
-> merdiven

== lamba_kontrol
-> {adim > 12} gec_kaldin
-> lamba_odasi

== lamba_odasi
Lamba odası baştan aşağı cam ve pirinç. Ortada büyük mercek duruyor, içinde de soğuk fitil.
{gaz > 0: Gaz bidonu yanında çalkalanıyor.|Fitilin haznesine vuruyorsun. Boş boş çınlıyor.}
* {gaz > 0 and kibrit} Hazneyi doldur ve fitili yak -> yandi
* {gaz > 0 and not kibrit} Yakacak bir şey ara -> ates_yok
* {gaz == 0} Gaz için aşağı in ~ adim += 1 -> merdiven

== ates_yok
Burada ateş yakacak hiçbir şey yok. Evdeki kibrit kutusunu düşünüyorsun: aşağıda, avlunun öbür ucunda.
* Kibrit için koş ~ adim += 3; kibrit = true -> lamba_kontrol

== yandi
Fitil tutuşuyor. Mercek küçük alevi bir ağaç gövdesi kalınlığında bir ışık huzmesine çeviriyor ve makine ağır ağır dönmeye başlıyor.
Denizde geminin iki ışığı duruyor. Sonra yavaşça resiften uzağa dönüyorlar.
* Sis çanının orada Tom'u ara -> can
* Sabaha kadar lambanın başında kal -> sabah

== can
Kayalıkların dibindeki sis çanının yanında bir fener yan yatmış duruyor. Yanında Tom, bileği altında burkulmuş, sırılsıklam ve öfkeli, duvara yaslanmış oturuyor.
"İki saattir bağırıyorum," diyor. "Sen de kimsin?"
Işık huzmesi tepenizde dönerken onu basamak basamak yukarı çıkarıyorsun.
-> en_iyi_son

== en_iyi_son
Sabaha doğru fırtına diniyor. Tom ayağı sandalyenin üstünde çayını içiyor ve telsizden sahil güvenliğe yeni bekçinin iş göreceğini söylüyor.
-> END

== sabah
Gökyüzü griye dönene kadar lambayı yanık tutuyorsun. Sabah teknesi geldiğinde Tom'u sis çanının yanında buluyorlar: bileği burkulmuş, üşümüş ama hayatta.
Gemi limana sağ salim vardı. Sen de lambadan gözünü hiç ayırmadın.
-> END

== gec_kaldin
Lamba odasına tam o anı görmeye yetişiyorsun: geminin ışıkları duruyor, yana yatıyor ve resifte sönüyor.
Cankurtaran sandalı sabah mürettebatı kayalara tutunmuş buluyor. Kimse ölmedi. Ama Martı Kayası'nda kimse fenerin karanlık kaldığı o geceyi unutmayacak.
-> END
