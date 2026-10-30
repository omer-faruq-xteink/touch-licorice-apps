title: Gece Treni
author: omer-faruq
language: tr
licence: CC BY 4.0
about: Sahile giden yataklı trende bir inci kolye kayboluyor. Sabaha kadar vaktin var. Yaklaşık on beş dakika.
start: peron
var: ipucu = 0
var: eldiven = false
var: bilet = false
var: duduk = false
var: saat = 0

== peron
Sahile giden yataklı tren saat onda kalkıyor. Son vagonda bir yerin, okumayacağın bir kitabın var ve hiçbir planın yok.
On bir buçukta üçüncü vagonda bir kadın çığlık atıyor.
* Gidip bak -> ciglik

== ciglik
Bayan Ada Varga sabahlığıyla koridorda durmuş, açık bir mücevher kutusunu gösteriyor. "İncilerim," diyor. "Ben yüzümü yıkarken biri almış. On dakika, daha fazla değil."
Kondüktör, Pim adında yorgun bir genç, sana bakıyor. "Polisiye okuyan birine benziyorsunuz. Polis ancak sahilde binecek. Yardım eder misiniz?"
* "Elbette." -> koridor

== koridor
~ saat += 1
{saat >= 6: Tarlaların üstünde gri bir ışık beliriyor. Tren yakında sahile varacak.|Tren karanlıkta sallanarak ilerliyor. Saat {saat < 2: gece yarısını yeni geçti|gece yarısını epey geçti}.}
Şimdiye kadar {ipucu} ipucu buldun.
Üçüncü vagonda kompartımanı olan üç yolcu daha var.
* {not eldiven} Pazarlamacı Bay Holm'la konuş -> holm
* {not bilet} Öğrenci Bayan Laine'le konuş -> laine
* {not duduk} Kompartımanından hiç çıkmayan Kont'la konuş -> kont
* [once] Koridoru ve lavaboyu ara -> arama
* {ipucu >= 2} Herkesi topla ve hırsızın adını söyle -> suclama
* {saat >= 6} Vazgeç ve polisi bekle -> vazgec

== holm
Bay Holm şemsiye satıyor ve bunu iki kez söylüyor. Uyuyormuş, hiçbir şey duymamış.
Ranzasının üstünde kuyumcuların taktığı türden beyaz pamuk eldivenler duruyor.
* "Bunlar sizin mi?" -> holm_eldiven
* Onu rahat bırak -> koridor

== holm_eldiven
Kızarıyor. "Numunelerimi bunlarla silerim. Şemsiyelerin gümüş sapları var, bilirsiniz." Gösteriyor: gerçekten de var.
Yine de not alıyorsun.
~ eldiven = true
~ ipucu += 1
-> koridor

== laine
Bayan Laine, Roma hukuku üzerine kalın bir kitap okuyor. Bir şey duymuş: on biri yirmi geçe bir kapı sesi, sonra trenin arkasına doğru hızlı ayak sesleri.
Bileti kitabın arasından ayraç gibi çıkıyor.
* Bilete bak -> laine_bilet
* Teşekkür et ve git -> koridor

== laine_bilet
Seninki gibi sahile giden bir bilet. Ama bu öğleden sonra, saat dokuzda kalkan bir tren için alınmış. Yanlış trende.
"Benimkini kaçırdım," diyor sakince. "Pim beni bindirdi. Ona sorun."
~ bilet = true
~ ipucu += 1
-> koridor

== kont
Kont kapısını bir parmak aralıyor. Gece yarısı olmasına rağmen tepeden tırnağa giyinik, paltosu bile üstünde. "Uykum hafiftir," diyor. "Kadının çığlığını duydum. O kadar."
* [once] Arkasından kompartımanın içine bak -> kont_bak
* Neden giyinik olduğunu sor -> kont_giyinik
* Ayrıl -> koridor

== kont_bak
Arkasında, küçük masanın üstünde, tren görevlilerinin kullandığı türden zincirli gümüş bir düdük duruyor.
"Hatıra," diyor ve kapıyı kapatıyor.
~ duduk = true
~ ipucu += 1
-> koridor

== kont_giyinik
"Sahile varmadan hep giyinirim. Hazır olmayı severim." Dişlerini göstermeden gülümsüyor. "İyi geceler."
-> koridor

== arama
Lavaboda, lavabonun altındaki borunun arkasında parmakların küçük, sert bir şeye değiyor: tek bir inci ve kısa, kopuk bir ip parçası.
Kolyeyi alan her kimse, trenin arkasına doğru bu yoldan geçmiş.
~ ipucu += 1
-> koridor

== suclama
Herkes koridora sıkışıyor: Bayan Varga, Bay Holm, Bayan Laine, Kont ve elinde lambasıyla Pim.
{ipucu >= 3: Bildiklerini gözden geçiriyorsun: ayak sesleri, borunun arkasındaki inci, görevli düdüğü.|Yeterince şey bildiğinden emin değilsin, ama hepsi sana bakıyor.}
* Bay Holm, kuyumcu eldivenleriyle -> yanlis_holm
* Bayan Laine, yanlış trendeki -> yanlis_laine
* Kont, giyinik ve gitmeye hazır -> yanlis_kont
* {duduk} Pim, kondüktör -> dogru

== yanlis_holm
Bay Holm şemsiye çantasını tek tek, sessizce yere boşaltıyor. İnci yok.
O hepsini yeniden toplayana kadar tren sahile varıyor ve polis biniyor. Kolyeyi asla bulamıyorlar.
-> END

== yanlis_laine
Bayan Laine kitabını kapatıyor. "Hukuk okuyorum," diyor. "Birini kanıtsız suçlamak ciddi bir iştir." Haklı, çantasında da kolye yok.
Polis sahilde herkesin adını alıyor. İncileri bir daha gören olmuyor.
-> END

== yanlis_kont
Kont gülüyor. Ceplerini boşaltıyor, valizini açıyor, hatta ayakkabılarını bile çıkarıyor. Hiçbir şey yok.
"Gitmeye hazırım," diyor, "çünkü kızım peronda bekliyor." Gerçekten de bekliyor. İnciler ise yok.
-> END

== dogru
"Pim," diyorsun. "Ayak sesleri arkaya doğru gitti. Arkada sadece görevli vagonu var. Kont'ta da hatıra dediği bir görevli düdüğü var. Seninkini nerede düşürdün?"
Pim'in lambası titriyor. Kont iç çekiyor. "Koşarken kapımın önüne düşürdü. Ben de aldım. Bir çocuğun başını belaya sokmak istemedim."
Görevli vagonunda, sobanın kömürünün altında Bayan Varga'nın incilerini buluyorsun, bir tanesi eksik.
{ipucu >= 4: Cebindeki son inciyi ona veriyorsun ve kadın yüksek sesle gülüyor.|İki kez sayıyor ve eksik olan hakkında hiçbir şey söylemiyor.}
-> END

== vazgec
Kompartımanına oturup güneşin doğuşunu izliyorsun. Sahilde polis iki saat boyunca herkesin bavulunu arıyor.
İncileri kimse bulamıyor. Bazı sabahlar hâlâ merak ediyorsun.
-> END
