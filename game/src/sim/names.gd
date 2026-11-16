class_name Names
extends RefCounted
## Uzbek names for generated players.

const SURNAMES := [
	"Karimov", "Rahimov", "Toshmatov", "Yusupov", "Abdullayev", "Ergashev", "Sobirov",
	"Nazarov", "Xolmatov", "Shukurov", "Tursunov", "Qodirov", "Azimov", "Mirzayev",
	"Hamidov", "Ismoilov", "Jo'rayev", "Sultonov", "Umarov", "Murodov", "Saidov",
	"Aliyev", "Alimov", "Boboyev", "G'aniyev", "Haydarov", "Islomov", "Komilov",
	"Latipov", "Mahmudov", "Normatov", "Olimov", "Po'latov", "Qosimov", "Rasulov",
	"Salimov", "Tojiyev", "Usmonov", "Valiyev", "Xasanov", "Yo'ldoshev", "Zokirov",
	"Ahmedov", "Davronov", "Eshonqulov", "Fayzullayev", "Jalolov", "Mamatqulov",
	"Nurmatov", "Ochilov", "Rustamov", "Sharipov", "To'xtayev", "Begmatov", "Choriyev",
	"Dadajonov", "Egamberdiyev", "Gulomov", "Hakimov", "Ibragimov", "Juraqulov",
	"Kamolov", "Mavlonov", "Nishonov", "Odilov", "Parpiyev", "Qurbonov", "Raximberdiyev",
	"Safarov", "Temirov", "Usarov", "Xudoyberdiyev", "Yoqubov", "Zufarov", "Bakirov",
	"Erkinov", "Muminov", "Abdurahmonov", "Shermatov", "Turg'unov",
]

const FIRST := [
	"Jasur", "Sardor", "Bekzod", "Otabek", "Jamshid", "Sherzod", "Aziz", "Dilshod",
	"Eldor", "Farrux", "Islom", "Javohir", "Abbos", "Ulug'bek", "Sanjar", "Doston",
	"Shoxrux", "Temur", "Nodir", "Odil", "Rustam", "Bobur", "Asadbek", "Diyor",
	"Muhammadali", "Abdulaziz", "Xurshid", "Oybek", "Akmal", "Sherali", "Zafar",
	"Husan", "Hasan", "Ilhom", "Kamron", "Lazizbek", "Mirjalol", "Nurbek", "Saidakbar",
]

const DISTRICTS := [
	"Chilonzor", "Yunusobod", "Mirzo Ulug'bek", "Yakkasaroy", "Shayxontohur", "Olmazor",
	"Sergeli", "Uchtepa", "Yashnobod", "Bektemir", "Mirobod", "Yangihayot",
]

const REGIONS := [
	"Toshkent", "Samarqand", "Buxoro", "Farg'ona", "Andijon", "Namangan", "Qashqadaryo",
	"Surxondaryo", "Xorazm", "Navoiy", "Jizzax", "Sirdaryo", "Qoraqalpog'iston",
]


static func random_surname(rng: RandomNumberGenerator) -> String:
	return SURNAMES[rng.randi() % SURNAMES.size()]


static func random_first(rng: RandomNumberGenerator) -> String:
	return FIRST[rng.randi() % FIRST.size()]
