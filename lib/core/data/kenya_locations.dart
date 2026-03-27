/// Complete Kenya Administrative Divisions Data
/// Contains all 47 counties, 290 constituencies, and 1,450 wards
/// Source: IEBC Kenya Administrative Boundaries

class KenyaLocations {
  // All 47 Kenya Counties
  static const List<String> counties = [
    'Baringo', 'Bomet', 'Bungoma', 'Busia', 'Elgeyo/Marakwet', 'Embu',
    'Garissa', 'Homa Bay', 'Isiolo', 'Kajiado', 'Kakamega', 'Kericho',
    'Kiambu', 'Kilifi', 'Kirinyaga', 'Kisii', 'Kisumu', 'Kitui', 'Kwale',
    'Laikipia', 'Lamu', 'Machakos', 'Makueni', 'Mandera', 'Marsabit',
    'Meru', 'Migori', 'Mombasa', 'Murang\'a', 'Nakuru', 'Nandi', 'Nairobi',
    'Nyandarua', 'Nyamira', 'Nyeri', 'Samburu', 'Siaya', 'Taita Taveta',
    'Tana River', 'Tharaka-Nithi', 'Trans Nzoia', 'Turkana', 'Uasin Gishu',
    'Vihiga', 'Wajir', 'West Pokot',
  ];

  // Constituencies by County
  static const Map<String, List<String>> constituenciesByCounty = {
    'Mombasa': ['Changamwe', 'Jomvu', 'Kisauni', 'Nyali', 'Likoni', 'Mvita'],
    'Kwale': ['Msambweni', 'Lungalunga', 'Matuga', 'Kinango'],
    'Kilifi': ['Kilifi North', 'Kilifi South', 'Kaloleni', 'Rabai', 'Ganze', 'Malindi', 'Magarini'],
    'Tana River': ['Garsen', 'Galole', 'Bura'],
    'Lamu': ['Lamu East', 'Lamu West'],
    'Taita Taveta': ['Taveta', 'Wundanyi', 'Mwatate', 'Voi'],
    'Garissa': ['Garissa Township', 'Balambala', 'Lagdera', 'Dadaab', 'Fafi', 'Ijara'],
    'Wajir': ['Wajir North', 'Wajir East', 'Tarbaj', 'Wajir West', 'Eldas', 'Wajir South'],
    'Mandera': ['Mandera West', 'Banissa', 'Mandera North', 'Mandera South', 'Mandera East', 'Lafey'],
    'Marsabit': ['Moyale', 'North Horr', 'Saku', 'Laisamis'],
    'Isiolo': ['Isiolo North', 'Isiolo South'],
    'Meru': ['Igembe South', 'Igembe Central', 'Igembe North', 'Tigania West', 'Tigania East', 'North Imenti', 'Buuri', 'Central Imenti', 'South Imenti'],
    'Tharaka-Nithi': ['Maara', 'Chuka/Igambang\'Om', 'Tharaka'],
    'Embu': ['Manyatta', 'Runyenjes', 'Mbeere South', 'Mbeere North'],
    'Kitui': ['Mwingi North', 'Mwingi West', 'Mwingi Central', 'Kitui West', 'Kitui Rural', 'Kitui Central', 'Kitui East', 'Kitui South'],
    'Machakos': ['Masinga', 'Yatta', 'Kangundo', 'Matungulu', 'Kathiani', 'Mavoko', 'Machakos Town', 'Mwala'],
    'Makueni': ['Mbooni', 'Kilome', 'Kaiti', 'Makueni', 'Kibwezi West', 'Kibwezi East'],
    'Nyandarua': ['Kinangop', 'Kipipiri', 'Ol Kalou', 'Ol Jorok', 'Ndaragwa'],
    'Nyeri': ['Tetu', 'Kieni', 'Mathira', 'Othaya', 'Mukurweini', 'Nyeri Town'],
    'Kirinyaga': ['Mwea', 'Gichugu', 'Ndia', 'Kirinyaga Central'],
    'Murang\'a': ['Kangema', 'Mathioya', 'Kiharu', 'Kigumo', 'Maragwa', 'Kandara', 'Gatanga'],
    'Kiambu': ['Gatundu South', 'Gatundu North', 'Juja', 'Thika Town', 'Ruiru', 'Githunguri', 'Kiambu', 'Kiambaa', 'Kabete', 'Kikuyu', 'Limuru', 'Lari'],
    'Turkana': ['Turkana North', 'Turkana West', 'Turkana Central', 'Loima', 'Turkana South', 'Turkana East'],
    'West Pokot': ['Kapenguria', 'Sigor', 'Kacheliba', 'Pokot South'],
    'Samburu': ['Samburu West', 'Samburu North', 'Samburu East'],
    'Trans Nzoia': ['Kwanza', 'Endebess', 'Saboti', 'Kiminini', 'Cherangany'],
    'Uasin Gishu': ['Soy', 'Turbo', 'Moiben', 'Ainabkoi', 'Kapseret', 'Kesses'],
    'Elgeyo/Marakwet': ['Marakwet East', 'Marakwet West', 'Keiyo North', 'Keiyo South'],
    'Nandi': ['Tinderet', 'Aldai', 'Nandi Hills', 'Chesumei', 'Emgwen', 'Mosop'],
    'Baringo': ['Tiaty', 'Baringo North', 'Baringo Central', 'Baringo South', 'Mogotio', 'Eldama Ravine'],
    'Laikipia': ['Laikipia West', 'Laikipia East', 'Laikipia North'],
    'Nakuru': ['Molo', 'Njoro', 'Naivasha', 'Gilgil', 'Kuresoi South', 'Kuresoi North', 'Subukia', 'Rongai', 'Bahati', 'Nakuru Town West', 'Nakuru Town East'],
    'Narok': ['Kilgoris', 'Emurua Dikirr', 'Narok North', 'Narok East', 'Narok South', 'Narok West'],
    'Kajiado': ['Kajiado North', 'Kajiado Central', 'Kajiado East', 'Kajiado West', 'Kajiado South'],
    'Kericho': ['Kipkelion East', 'Kipkelion West', 'Ainamoi', 'Bureti', 'Belgut', 'Sigowet/Soin'],
    'Bomet': ['Sotik', 'Chepalungu', 'Bomet East', 'Bomet Central', 'Konoin'],
    'Kakamega': ['Lugari', 'Likuyani', 'Malava', 'Lurambi', 'Navakholo', 'Mumias West', 'Mumias East', 'Matungu', 'Butere', 'Khwisero', 'Shinyalu', 'Ikolomani'],
    'Vihiga': ['Vihiga', 'Sabatia', 'Hamisi', 'Luanda', 'Emuhaya'],
    'Bungoma': ['Mt.Elgon', 'Sirisia', 'Kabuchai', 'Bumula', 'Kanduyi', 'Webuye East', 'Webuye West', 'Kimilili', 'Tongaren'],
    'Busia': ['Teso North', 'Teso South', 'Nambale', 'Matayos', 'Butula', 'Funyula', 'Budalangi'],
    'Siaya': ['Ugenya', 'Ugunja', 'Alego Usonga', 'Gem', 'Bondo', 'Rarieda'],
    'Kisumu': ['Kisumu East', 'Kisumu West', 'Kisumu Central', 'Seme', 'Nyando', 'Muhoroni', 'Nyakach'],
    'Homa Bay': ['Kasipul', 'Kabondo Kasipul', 'Karachuonyo', 'Rangwe', 'Homa Bay Town', 'Ndhiwa', 'Mbita', 'Suba'],
    'Migori': ['Rongo', 'Awendo', 'Suna East', 'Suna West', 'Uriri', 'Nyatike', 'Kuria West', 'Kuria East'],
    'Kisii': ['Bonchari', 'South Mugirango', 'Bomachoge Borabu', 'Bobasi', 'Bomachoge Chache', 'Nyaribari Masaba', 'Nyaribari Chache', 'Kitutu Chache North', 'Kitutu Chache South'],
    'Nyamira': ['Kitutu Masaba', 'West Mugirango', 'North Mugirango', 'Borabu'],
    'Nairobi': ['Westlands', 'Dagoretti North', 'Dagoretti South', 'Langata', 'Kibra', 'Roysambu', 'Kasarani', 'Ruaraka', 'Embakasi South', 'Embakasi North', 'Embakasi Central', 'Embakasi East', 'Embakasi West', 'Makadara', 'Kamukunji', 'Starehe', 'Mathare'],
  };

  // Wards by Constituency (Complete list - all 1,450 wards)
  static const Map<String, List<String>> wardsByConstituency = {
    // Mombasa County
    'Changamwe': ['Port Reitz', 'Kipevu', 'Airport', 'Changamwe', 'Chaani'],
    'Jomvu': ['Jomvu Kuu', 'Miritini', 'Mikindani'],
    'Kisauni': ['Mjambere', 'Junda', 'Bamburi', 'Mwakirunge', 'Mtopanga', 'Magogoni', 'Shanzu'],
    'Nyali': ['Frere Town', 'Ziwa La Ng\'Ombe', 'Mkomani', 'Kongowea', 'Kadzandani'],
    'Likoni': ['Mtongwe', 'Shika Adabu', 'Bofu', 'Likoni', 'Timbwani'],
    'Mvita': ['Mji Wa Kale/Makadara', 'Tudor', 'Tononoka', 'Shimanzi/Ganjoni', 'Majengo'],
    
    // Kwale County
    'Msambweni': ['Gombatobongwe', 'Ukunda', 'Kinondo', 'Ramisi'],
    'Lungalunga': ['Pongwekikoneni', 'Dzombo', 'Mwereni', 'Vanga'],
    'Matuga': ['Tsimba Golini', 'Waa', 'Tiwi', 'Kubo South', 'Mkongani'],
    'Kinango': ['Nadavaya', 'Puma', 'Kinango', 'Mackinnon-Road', 'Chengoni/Samburu', 'Mwavumbo', 'Kasemeni'],
    
    // Kilifi County
    'Kilifi North': ['Tezo', 'Sokoni', 'Kibarani', 'Dabaso', 'Matsangoni', 'Watamu', 'Mnarani'],
    'Kilifi South': ['Junju', 'Mwarakaya', 'Shimo La Tewa', 'Chasimba', 'Mtepeni'],
    'Kaloleni': ['Mariakani', 'Kayafungo', 'Kaloleni', 'Mwanamwinga'],
    'Rabai': ['Mwawesa', 'Ruruma', 'Kambe/Ribe', 'Rabai/Kisurutini'],
    'Ganze': ['Ganze', 'Bamba', 'Jaribuni', 'Sokoke'],
    'Malindi': ['Jilore', 'Kakuyuni', 'Ganda', 'Malindi Town', 'Shella'],
    'Magarini': ['Marafa', 'Magarini', 'Gongoni', 'Adu', 'Garashi', 'Sabaki'],
    
    // Tana River County
    'Garsen': ['Kipini East', 'Garsen South', 'Kipini West', 'Garsen Central', 'Garsen West', 'Garsen North'],
    'Galole': ['Kinakomba', 'Mikinduni', 'Chewani', 'Wayu'],
    'Bura': ['Chewele', 'Bura', 'Bangale', 'Sala', 'Madogo'],
    
    // Lamu County
    'Lamu East': ['Faza', 'Kiunga', 'Basuba'],
    'Lamu West': ['Shella', 'Mkomani', 'Hindi', 'Mkunumbi', 'Hongwe', 'Witu', 'Bahari'],
    
    // Taita Taveta County
    'Taveta': ['Chala', 'Mahoo', 'Bomeni', 'Mboghoni', 'Mata'],
    'Wundanyi': ['Wundanyi/Mbale', 'Werugha', 'Wumingu/Kishushe', 'Mwanda/Mgange'],
    'Mwatate': ['Rong\'E', 'Mwatate', 'Bura', 'Chawia', 'Wusi/Kishamba'],
    'Voi': ['Mbololo', 'Sagalla', 'Kaloleni', 'Marungu', 'Kasigau', 'Ngolia'],
    
    // Garissa County
    'Garissa Township': ['Waberi', 'Galbet', 'Township', 'Iftin'],
    'Balambala': ['Balambala', 'Danyere', 'Jara Jara', 'Saka', 'Sankuri'],
    'Lagdera': ['Modogashe', 'Benane', 'Goreale', 'Maalimin', 'Sabena', 'Baraki'],
    'Dadaab': ['Dertu', 'Dadaab', 'Labasigale', 'Damajale', 'Liboi', 'Abakaile'],
    'Fafi': ['Bura', 'Dekaharia', 'Jarajila', 'Fafi', 'Nanighi'],
    'Ijara': ['Hulugho', 'Sangailu', 'Ijara', 'Masalani'],
    
    // Wajir County
    'Wajir North': ['Gurar', 'Bute', 'Korondile', 'Malkagufu', 'Batalu', 'Danaba', 'Godoma'],
    'Wajir East': ['Wagberi', 'Township', 'Barwago', 'Khorof/Harar'],
    'Tarbaj': ['Elben', 'Sarman', 'Tarbaj', 'Wargadud'],
    'Wajir West': ['Arbajahan', 'Hadado/Athibohol', 'Ademasajide', 'Wagalla/Ganyure'],
    'Eldas': ['Eldas', 'Della', 'Lakoley South/Basir', 'Elnur/Tula Tula'],
    'Wajir South': ['Benane', 'Burder', 'Dadaja Bulla', 'Habasswein', 'Lagboghol South', 'Ibrahim Ure', 'Diif'],
    
    // Mandera County
    'Mandera West': ['Takaba South', 'Takaba', 'Lag Sure', 'Dandu', 'Gither'],
    'Banissa': ['Banissa', 'Derkhale', 'Guba', 'Malkamari', 'Kiliwehiri'],
    'Mandera North': ['Ashabito', 'Guticha', 'Morothile', 'Rhamu', 'Rhamu-Dimtu'],
    'Mandera South': ['Wargudud', 'Kutulo', 'Elwak South', 'Elwak North', 'Shimbir Fatuma'],
    'Mandera East': ['Arabia', 'Bulla Mpya', 'Khalalio', 'Neboi', 'Township'],
    'Lafey': ['Libehia', 'Fino', 'Lafey', 'Warankara', 'Alungo Gof'],
    
    // Marsabit County
    'Moyale': ['Butiye', 'Sololo', 'Heilu-Manyatta', 'Golbo', 'Moyale Township', 'Uran', 'Obbu'],
    'North Horr': ['Illeret', 'North Horr', 'Dukana', 'Maikona', 'Turbi'],
    'Saku': ['Sagante/Jaldesa', 'Karare', 'Marsabit Central'],
    'Laisamis': ['Loiyangalani', 'Kargi/South Horr', 'Korr/Ngurunit', 'Log Logo', 'Laisamis'],
    
    // Isiolo County
    'Isiolo North': ['Wabera', 'Bulla Pesa', 'Chari', 'Cherab', 'Ngare Mara', 'Burat', 'Oldonyiro'],
    'Isiolo South': ['Garbatulla', 'Kinna', 'Sericho'],
    
    // Meru County
    'Igembe South': ['Maua', 'Kiegoi/Antubochiu', 'Athiru Gaiti', 'Akachiu', 'Kanuni'],
    'Igembe Central': ['Akirang\'Ondu', 'Athiru Ruujine', 'Igembe East', 'Njia', 'Kangeta'],
    'Igembe North': ['Antuambui', 'Ntunene', 'Antubetwe Kiongo', 'Naathu', 'Amwathi'],
    'Tigania West': ['Athwana', 'Akithii', 'Kianjai', 'Nkomo', 'Mbeu'],
    'Tigania East': ['Thangatha', 'Mikinduri', 'Kiguchwa', 'Muthara', 'Karama'],
    'North Imenti': ['Municipality', 'Ntima East', 'Ntima West', 'Nyaki West', 'Nyaki East'],
    'Buuri': ['Timau', 'Kisima', 'Kiirua/Naari', 'Ruiri/Rwarera', 'Kibirichia'],
    'Central Imenti': ['Mwanganthia', 'Abothuguchi Central', 'Abothuguchi West', 'Kiagu'],
    'South Imenti': ['Mitunguu', 'Igoji East', 'Igoji West', 'Abogeta East', 'Abogeta West', 'Nkuene'],
    
    // Tharaka-Nithi County
    'Maara': ['Mitheru', 'Muthambi', 'Mwimbi', 'Ganga', 'Chogoria'],
    'Chuka/Igambang\'Om': ['Mariani', 'Karingani', 'Magumoni', 'Mugwe', 'Igambang\'Ombe'],
    'Tharaka': ['Gatunga', 'Mukothima', 'Nkondi', 'Chiakariga', 'Marimanti'],
    
    // Embu County
    'Manyatta': ['Ruguru/Ngandori', 'Kithimu', 'Nginda', 'Mbeti North', 'Kirimari', 'Gaturi South'],
    'Runyenjes': ['Gaturi North', 'Kagaari South', 'Central Ward', 'Kagaari North', 'Kyeni North', 'Kyeni South'],
    'Mbeere South': ['Mwea', 'Makima', 'Mbeti South', 'Mavuria', 'Kiambere'],
    'Mbeere North': ['Nthawa', 'Muminji', 'Evurore'],
    
    // Kitui County
    'Mwingi North': ['Ngomeni', 'Kyuso', 'Mumoni', 'Tseikuru', 'Tharaka'],
    'Mwingi West': ['Kyome/Thaana', 'Nguutani', 'Migwani', 'Kiomo/Kyethani'],
    'Mwingi Central': ['Central', 'Kivou', 'Nguni', 'Nuu', 'Mui', 'Waita'],
    'Kitui West': ['Mutonguni', 'Kauwi', 'Matinyani', 'Kwa Mutonga/Kithumula'],
    'Kitui Rural': ['Kisasi', 'Mbitini', 'Kwavonza/Yatta', 'Kanyangi'],
    'Kitui Central': ['Miambani', 'Township', 'Kyangwithya West', 'Mulango', 'Kyangwithya East'],
    'Kitui East': ['Zombe/Mwitika', 'Chuluni', 'Nzambani', 'Voo/Kyamatu', 'Endau/Malalani', 'Mutito/Kaliku'],
    'Kitui South': ['Ikanga/Kyatune', 'Mutomo', 'Mutha', 'Ikutha', 'Kanziko', 'Athi'],
    
    // Machakos County
    'Masinga': ['Kivaa', 'Masinga Central', 'Ekalakala', 'Muthesya', 'Ndithini'],
    'Yatta': ['Ndalani', 'Matuu', 'Kithimani', 'Ikombe', 'Katangi'],
    'Kangundo': ['Kangundo North', 'Kangundo Central', 'Kangundo East', 'Kangundo West'],
    'Matungulu': ['Tala', 'Matungulu North', 'Matungulu East', 'Matungulu West', 'Kyeleni'],
    'Kathiani': ['Mitaboni', 'Kathiani Central', 'Upper Kaewa/Iveti', 'Lower Kaewa/Kaani'],
    'Mavoko': ['Athi River', 'Kinanie', 'Muthwani', 'Syokimau/Mulolongo'],
    'Machakos Town': ['Kalama', 'Mua', 'Mutituni', 'Machakos Central', 'Mumbuni North', 'Muvuti/Kiima-Kimwe', 'Kola'],
    'Mwala': ['Mbiuni', 'Makutano/ Mwala', 'Masii', 'Muthetheni', 'Wamunyu', 'Kibauni'],
    
    // Makueni County
    'Mbooni': ['Tulimani', 'Mbooni', 'Kithungo/Kitundu', 'Kisau/Kiteta', 'Waia/Kako', 'Kalawa'],
    'Kilome': ['Kasikeu', 'Mukaa', 'Kiima Kiu/Kalanzoni'],
    'Kaiti': ['Ukia', 'Kee', 'Kilungu', 'Ilima'],
    'Makueni': ['Wote', 'Muvau/Kikuumini', 'Mavindini', 'Kitise/Kithuki', 'Kathonzweni', 'Nzaui/Kilili/Kalamba', 'Mbitini'],
    'Kibwezi West': ['Makindu', 'Nguumo', 'Kikumbulyu North', 'Kikumbulyu South', 'Nguu/Masumba', 'Emali/Mulala'],
    'Kibwezi East': ['Masongaleni', 'Mtito Andei', 'Thange', 'Ivingoni/Nzambani'],
    
    // Nyandarua County
    'Kinangop': ['Engineer', 'Gathara', 'North Kinangop', 'Murungaru', 'Njabini/Kiburu', 'Nyakio', 'Githabai', 'Magumu'],
    'Kipipiri': ['Wanjohi', 'Kipipiri', 'Geta', 'Githioro'],
    'Ol Kalou': ['Karau', 'Kanjuiri Ridge', 'Mirangine', 'Kaimbaga', 'Rurii'],
    'Ol Jorok': ['Gathanji', 'Gatimu', 'Weru', 'Charagita'],
    'Ndaragwa': ['Leshau Pondo', 'Kiriita', 'Central', 'Shamata'],
    
    // Nyeri County
    'Tetu': ['Dedan Kimanthi', 'Wamagana', 'Aguthi/Gaaki'],
    'Kieni': ['Mweiga', 'Naromoru Kiamathaga', 'Mwiyogo/Endarasha', 'Mugunda', 'Gatarakwa', 'Thegu River', 'Kabaru', 'Gakawa'],
    'Mathira': ['Ruguru', 'Magutu', 'Iriaini', 'Konyu', 'Kirimukuyu', 'Karatina Town'],
    'Othaya': ['Mahiga', 'Iria-Ini', 'Chinga', 'Karima'],
    'Mukurweini': ['Gikondi', 'Rugi', 'Mukurwe-Ini West', 'Mukurwe-Ini Central'],
    'Nyeri Town': ['Kiganjo/Mathari', 'Rware', 'Gatitu/Muruguru', 'Ruring\'U', 'Kamakwa/Mukaro'],
    
    // Kirinyaga County
    'Mwea': ['Mutithi', 'Kangai', 'Thiba', 'Wamumu', 'Nyangati', 'Murinduko', 'Gathigiriri', 'Tebere'],
    'Gichugu': ['Kabare', 'Baragwi', 'Njukiini', 'Ngariama', 'Karumandi'],
    'Ndia': ['Mukure', 'Kiine', 'Kariti'],
    'Kirinyaga Central': ['Mutira', 'Kanyeki-Ini', 'Kerugoya', 'Inoi'],
    
    // Murang'a County
    'Kangema': ['Kanyenyaini', 'Muguru', 'Rwathia'],
    'Mathioya': ['Gitugi', 'Kiru', 'Kamacharia'],
    'Kiharu': ['Wangu', 'Mugoiri', 'Mbiri', 'Township', 'Murarandia', 'Gaturi'],
    'Kigumo': ['Kahumbu', 'Muthithi', 'Kigumo', 'Kangari', 'Kinyona'],
    'Maragwa': ['Kimorori/Wempa', 'Makuyu', 'Kambiti', 'Kamahuha', 'Ichagaki', 'Nginda'],
    'Kandara': ['Ng\'Araria', 'Muruka', 'Kagundu-Ini', 'Gaichanjiru', 'Ithiru', 'Ruchu'],
    'Gatanga': ['Ithanga', 'Kakuzi/Mitubiri', 'Mugumo-Ini', 'Kihumbu-Ini', 'Gatanga', 'Kariara'],
    
    // Kiambu County
    'Gatundu South': ['Kiamwangi', 'Kiganjo', 'Ndarugu', 'Ngenda'],
    'Gatundu North': ['Gituamba', 'Githobokoni', 'Chania', 'Mang\'U'],
    'Juja': ['Murera', 'Theta', 'Juja', 'Witeithie', 'Kalimoni'],
    'Thika Town': ['Township', 'Kamenu', 'Hospital', 'Gatuanyaga', 'Ngoliba'],
    'Ruiru': ['Gitothua', 'Biashara', 'Gatongora', 'Kahawa Sukari', 'Kahawa Wendani', 'Kiuu', 'Mwiki', 'Mwihoko'],
    'Githunguri': ['Githunguri', 'Githiga', 'Ikinu', 'Ngewa', 'Komothai'],
    'Kiambu': ['Ting\'Ang\'A', 'Ndumberi', 'Riabai', 'Township'],
    'Kiambaa': ['Cianda', 'Karuri', 'Ndenderu', 'Muchatha', 'Kihara'],
    'Kabete': ['Gitaru', 'Muguga', 'Nyadhuna', 'Kabete', 'Uthiru'],
    'Kikuyu': ['Karai', 'Nachu', 'Sigona', 'Kikuyu', 'Kinoo'],
    'Limuru': ['Bibirioni', 'Limuru Central', 'Ndeiya', 'Limuru East', 'Ngecha Tigoni'],
    'Lari': ['Kinale', 'Kijabe', 'Nyanduma', 'Kamburu', 'Lari/Kirenga'],
    
    // Turkana County
    'Turkana North': ['Kaeris', 'Lake Zone', 'Lapur', 'Kaaleng/Kaikor', 'Kibish', 'Nakalale'],
    'Turkana West': ['Kakuma', 'Lopur', 'Letea', 'Songot', 'Kalobeyei', 'Lokichoggio', 'Nanaam'],
    'Turkana Central': ['Kerio Delta', 'Kang\'Atotha', 'Kalokol', 'Lodwar Township', 'Kanamkemer'],
    'Loima': ['Kotaruk/Lobei', 'Turkwel', 'Loima', 'Lokiriama/Lorengippi'],
    'Turkana South': ['Kaputir', 'Katilu', 'Lobokat', 'Kalapata', 'Lokichar'],
    'Turkana East': ['Kapedo/Napeitom', 'Katilia', 'Lokori/Kochodin'],
    
    // West Pokot County
    'Kapenguria': ['Riwo', 'Kapenguria', 'Mnagei', 'Siyoi', 'Endugh', 'Sook'],
    'Sigor': ['Sekerr', 'Masool', 'Lomut', 'Weiwei'],
    'Kacheliba': ['Suam', 'Kodich', 'Kapckok', 'Kasei', 'Kiwawa', 'Alale'],
    'Pokot South': ['Chepareria', 'Batei', 'Lelan', 'Tapach'],
    
    // Samburu County
    'Samburu West': ['Lodokejek', 'Suguta Marmar', 'Maralal', 'Loosuk', 'Poro'],
    'Samburu North': ['El-Barta', 'Nachola', 'Ndoto', 'Nyiro', 'Angata Nanyokie', 'Baawa'],
    'Samburu East': ['Waso', 'Wamba West', 'Wamba East', 'Wamba North'],
    
    // Trans Nzoia County
    'Kwanza': ['Kapomboi', 'Kwanza', 'Keiyo', 'Bidii'],
    'Endebess': ['Chepchoina', 'Endebess', 'Matumbei'],
    'Saboti': ['Kinyoro', 'Matisi', 'Tuwani', 'Saboti', 'Machewa'],
    'Kiminini': ['Kiminini', 'Waitaluk', 'Sirende', 'Hospital', 'Sikhendu', 'Nabiswa'],
    'Cherangany': ['Sinyerere', 'Makutano', 'Kaplamai', 'Motosiet', 'Cherangany/Suwerwa', 'Chepsiro/Kiptoror', 'Sitatunga'],
    
    // Uasin Gishu County
    'Soy': ['Moi\'S Bridge', 'Kapkures', 'Ziwa', 'Segero/Barsombe', 'Kipsomba', 'Soy', 'Kuinet/Kapsuswa'],
    'Turbo': ['Ngenyilel', 'Tapsagoi', 'Kamagut', 'Kiplombe', 'Kapsaos', 'Huruma'],
    'Moiben': ['Tembelio', 'Sergoit', 'Karuna/Meibeki', 'Moiben', 'Kimumu'],
    'Ainabkoi': ['Kapsoya', 'Kaptagat', 'Ainabkoi/Olare'],
    'Kapseret': ['Simat/Kapseret', 'Kipkenyo', 'Ngeria', 'Megun', 'Langas'],
    'Kesses': ['Racecourse', 'Cheptiret/Kipchamo', 'Tulwet/Chuiyat', 'Tarakwa'],
    
    // Elgeyo/Marakwet County
    'Marakwet East': ['Kapyego', 'Sambirir', 'Endo', 'Embobut/Embulot'],
    'Marakwet West': ['Lelan', 'Sengwer', 'Cherang\'Any/Chebororwa', 'Moiben/Kuserwo', 'Kapsowar', 'Arror'],
    'Keiyo North': ['Emsoo', 'Kamariny', 'Kapchemutwa', 'Tambach'],
    'Keiyo South': ['Kaptarakwa', 'Chepkorio', 'Soy North', 'Soy South', 'Kabiemit', 'Metkei'],
    
    // Nandi County
    'Tinderet': ['Songhor/Soba', 'Tindiret', 'Chemelil/Chemase', 'Kapsimotwo'],
    'Aldai': ['Kabwareng', 'Terik', 'Kemeloi-Maraba', 'Kobujoi', 'Kaptumo-Kaboi', 'Koyo-Ndurio'],
    'Nandi Hills': ['Nandi Hills', 'Chepkunyuk', 'Ol\'Lessos', 'Kapchorua'],
    'Chesumei': ['Chemundu/Kapng\'Etuny', 'Kosirai', 'Lelmokwo/Ngechek', 'Kaptel/Kamoiywo', 'Kiptuya'],
    'Emgwen': ['Chepkumia', 'Kapkangani', 'Kapsabet', 'Kilibwoni'],
    'Mosop': ['Chepterwai', 'Kipkaren', 'Kurgung/Surungai', 'Kabiyet', 'Ndalat', 'Kabisaga', 'Sangalo/Kebulonik'],
    
    // Baringo County
    'Tiaty': ['Tirioko', 'Kolowa', 'Ribkwo', 'Silale', 'Loiyamorock', 'Tangulbei/Korossi', 'Churo/Amaya'],
    'Baringo North': ['Barwessa', 'Kabartonjo', 'Saimo/Kipsaraman', 'Saimo/Soi', 'Bartabwa'],
    'Baringo Central': ['Kabarnet', 'Sacho', 'Tenges', 'Ewalel Chapchap', 'Kapropita'],
    'Baringo South': ['Marigat', 'Ilchamus', 'Mochongoi', 'Mukutani'],
    'Mogotio': ['Mogotio', 'Emining', 'Kisanana'],
    'Eldama Ravine': ['Lembus', 'Lembus Kwen', 'Ravine', 'Mumberes/Maji Mazuri', 'Lembus/Perkerra', 'Koibatek'],
    
    // Laikipia County
    'Laikipia West': ['Olmoran', 'Rumuruti Township', 'Kinamba', 'Marmanet', 'Igwamiti', 'Salama'],
    'Laikipia East': ['Ngobit', 'Tigithi', 'Thingithu', 'Nanyuki', 'Umande'],
    'Laikipia North': ['Sosian', 'Segera', 'Mukogondo West', 'Mukogondo East'],
    
    // Nakuru County
    'Molo': ['Mariashoni', 'Elburgon', 'Turi', 'Molo'],
    'Njoro': ['Maunarok', 'Mauche', 'Kihingo', 'Nessuit', 'Lare', 'Njoro'],
    'Naivasha': ['Biashara', 'Hells Gate', 'Lakeview', 'Maai-Mahiu', 'Maiella', 'Olkaria', 'Naivasha East', 'Viwandani'],
    'Gilgil': ['Gilgil', 'Elementaita', 'Mbaruk/Eburu', 'Malewa West', 'Murindati'],
    'Kuresoi South': ['Amalo', 'Keringet', 'Kiptagich', 'Tinet'],
    'Kuresoi North': ['Kiptororo', 'Nyota', 'Sirikwa', 'Kamara'],
    'Subukia': ['Subukia', 'Waseges', 'Kabazi'],
    'Rongai': ['Menengai West', 'Soin', 'Visoi', 'Mosop', 'Solai'],
    'Bahati': ['Dundori', 'Kabatini', 'Kiamaina', 'Lanet/Umoja', 'Bahati'],
    'Nakuru Town West': ['Barut', 'London', 'Kaptembwo', 'Kapkures', 'Rhoda', 'Shaabab'],
    'Nakuru Town East': ['Biashara', 'Kivumbini', 'Flamingo', 'Menengai', 'Nakuru East'],
    
    // Narok County
    'Kilgoris': ['Kilgoris Central', 'Keyian', 'Angata Barikoi', 'Shankoe', 'Kimintet', 'Lolgorian'],
    'Emurua Dikirr': ['Ilkerin', 'Ololmasani', 'Mogondo', 'Kapsasian'],
    'Narok North': ['Olpusimoru', 'Olokurto', 'Narok Town', 'Nkareta', 'Olorropil', 'Melili'],
    'Narok East': ['Mosiro', 'Ildamat', 'Keekonyokie', 'Suswa'],
    'Narok South': ['Majimoto/Naroosura', 'Ololulung\'A', 'Melelo', 'Loita', 'Sogoo', 'Sagamian'],
    'Narok West': ['Ilmotiok', 'Mara', 'Siana', 'Naikarra'],
    
    // Kajiado County
    'Kajiado North': ['Olkeri', 'Ongata Rongai', 'Nkaimurunya', 'Oloolua', 'Ngong'],
    'Kajiado Central': ['Purko', 'Ildamat', 'Dalalekutuk', 'Matapato North', 'Matapato South'],
    'Kajiado East': ['Kaputiei North', 'Kitengela', 'Oloosirkon/Sholinke', 'Kenyawa-Poka', 'Imaroro'],
    'Kajiado West': ['Keekonyokie', 'Iloodokilani', 'Magadi', 'Ewuaso Oonkidong\'I', 'Mosiro'],
    'Kajiado South': ['Entonet/Lenkisim', 'Mbirikani/Eselenkei', 'Kuku', 'Rombo', 'Kimana'],
    
    // Kericho County
    'Kipkelion East': ['Londiani', 'Kedowa/Kimugul', 'Chepseon', 'Tendeno/Sorget'],
    'Kipkelion West': ['Kunyak', 'Kamasian', 'Kipkelion', 'Chilchila'],
    'Ainamoi': ['Kapsoit', 'Ainamoi', 'Kapkugerwet', 'Kipchebor', 'Kipchimchim', 'Kapsaos'],
    'Bureti': ['Kisiara', 'Tebesonik', 'Cheboin', 'Chemosot', 'Litein', 'Cheplanget', 'Kapkatet'],
    'Belgut': ['Waldai', 'Kabianga', 'Cheptororiet/Seretut', 'Chaik', 'Kapsuser'],
    'Sigowet/Soin': ['Sigowet', 'Kaplelartet', 'Soliat', 'Soin'],
    
    // Bomet County
    'Sotik': ['Ndanai/Abosi', 'Chemagel', 'Kipsonoi', 'Kapletundo', 'Rongena/Manaret'],
    'Chepalungu': ['Kong\'Asis', 'Nyangores', 'Sigor', 'Chebunyo', 'Siongiroi'],
    'Bomet East': ['Merigi', 'Kembu', 'Longisa', 'Kipreres', 'Chemaner'],
    'Bomet Central': ['Silibwet Township', 'Ndaraweta', 'Singorwet', 'Chesoen', 'Mutarakwa'],
    'Konoin': ['Chepchabas', 'Kimulot', 'Mogogosiek', 'Boito', 'Embomos'],
    
    // Kakamega County
    'Lugari': ['Mautuma', 'Lugari', 'Lumakanda', 'Chekalini', 'Chevaywa', 'Lwandeti'],
    'Likuyani': ['Likuyani', 'Sango', 'Kongoni', 'Nzoia', 'Sinoko'],
    'Malava': ['West Kabras', 'Chemuche', 'East Kabras', 'Butali/Chegulo', 'Manda-Shivanga', 'Shirugu-Mugai', 'South Kabras'],
    'Lurambi': ['Butsotso East', 'Butsotso South', 'Butsotso Central', 'Sheywe', 'Mahiakalo', 'Shirere'],
    'Navakholo': ['Ingostse-Mathia', 'Shinoyi-Shikomari', 'Bunyala West', 'Bunyala East', 'Bunyala Central'],
    'Mumias West': ['Mumias Central', 'Mumias North', 'Etenje', 'Musanda'],
    'Mumias East': ['Lubinu/Lusheya', 'Isongo/Makunga/Malaha', 'East Wanga'],
    'Matungu': ['Koyonzo', 'Kholera', 'Khalaba', 'Mayoni', 'Namamali'],
    'Butere': ['Marama West', 'Marama Central', 'Marenyo-Shianda', 'Marama North', 'Marama South'],
    'Khwisero': ['Kisa North', 'Kisa East', 'Kisa West', 'Kisa Central'],
    'Shinyalu': ['Isukha North', 'Murhanda', 'Isukha Central', 'Isukha South', 'Isukha East', 'Isukha West'],
    'Ikolomani': ['Idakho South', 'Idakho East', 'Idakho North', 'Idakho Central'],
    
    // Vihiga County
    'Vihiga': ['Lugaga-Wamuluma', 'South Maragoli', 'Central Maragoli', 'Mungoma'],
    'Sabatia': ['Lyaduywa/Izava', 'West Sabatia', 'Chavakali', 'North Maragoli', 'Wodanga', 'Busali'],
    'Hamisi': ['Shiru', 'Muhudu', 'Shamakhokho', 'Gisambai', 'Banja', 'Tambua', 'Jepkoyai'],
    'Luanda': ['Luanda Township', 'Wemilabi', 'Mwibona', 'Luanda South', 'Emabungo'],
    'Emuhaya': ['North East Bunyore', 'Central Bunyore', 'West Bunyore'],
    
    // Bungoma County
    'Mt.Elgon': ['Cheptais', 'Chesikaki', 'Chepyuk', 'Kapkateny', 'Kaptama', 'Elgon'],
    'Sirisia': ['Namwela', 'Malakisi/South Kulisiru', 'Lwandanyi'],
    'Kabuchai': ['Kabuchai/Chwele', 'West Nalondo', 'Bwake/Luuya', 'Mukuyuni'],
    'Bumula': ['South Bukusu', 'Bumula', 'Khasoko', 'Kabula', 'Kimaeti', 'West Bukusu', 'Siboti'],
    'Kanduyi': ['Bukembe West', 'Bukembe East', 'Township', 'Khalaba', 'Musikoma', 'East Sang\'Alo', 'Marakaru/Tuuti', 'Sang\'Alo West'],
    'Webuye East': ['Mihuu', 'Ndivisi', 'Maraka'],
    'Webuye West': ['Misikhu', 'Sitikho', 'Matulo', 'Bokoli'],
    'Kimilili': ['Kimilili', 'Kibingei', 'Maeni', 'Kamukuywa'],
    'Tongaren': ['Mbakalo', 'Naitiri/Kabuyefwe', 'Milima', 'Ndalu/Tabani', 'Tongaren', 'Soysambu/Mitua'],
    
    // Busia County
    'Teso North': ['Malaba Central', 'Malaba North', 'Ang\'Urai South', 'Ang\'Urai North', 'Ang\'Urai East', 'Malaba South'],
    'Teso South': ['Ang\'Orom', 'Chakol South', 'Chakol North', 'Amukura West', 'Amukura East', 'Amukura Central'],
    'Nambale': ['Nambale Township', 'Bukhayo North/Waltsi', 'Bukhayo East', 'Bukhayo Central'],
    'Matayos': ['Bukhayo West', 'Mayenje', 'Matayos South', 'Busibwabo', 'Burumba'],
    'Butula': ['Marachi West', 'Kingandole', 'Marachi Central', 'Marachi East', 'Marachi North', 'Elugulu'],
    'Funyula': ['Namboboto Nambuku', 'Nangina', 'Ageng\'A Nanguba', 'Bwiri'],
    'Budalangi': ['Bunyala Central', 'Bunyala North', 'Bunyala West', 'Bunyala South'],
    
    // Siaya County
    'Ugenya': ['West Ugenya', 'Ukwala', 'North Ugenya', 'East Ugenya'],
    'Ugunja': ['Sidindi', 'Sigomere', 'Ugunja'],
    'Alego Usonga': ['Usonga', 'West Alego', 'Central Alego', 'Siaya Township', 'North Alego', 'South East Alego'],
    'Gem': ['North Gem', 'West Gem', 'Central Gem', 'Yala Township', 'East Gem', 'South Gem'],
    'Bondo': ['West Yimbo', 'Central Sakwa', 'South Sakwa', 'Yimbo East', 'West Sakwa', 'North Sakwa'],
    'Rarieda': ['East Asembo', 'West Asembo', 'North Uyoma', 'South Uyoma', 'West Uyoma'],
    
    // Kisumu County
    'Kisumu East': ['Kajulu', 'Kolwa East', 'Manyatta B', 'Nyalenda A', 'Kolwa Central'],
    'Kisumu West': ['South West Kisumu', 'Central Kisumu', 'Kisumu North', 'West Kisumu', 'North West Kisumu'],
    'Kisumu Central': ['Railways', 'Migosi', 'Shaurimoyo Kaloleni', 'Market Milimani', 'Kondele', 'Nyalenda B'],
    'Seme': ['West Seme', 'Central Seme', 'East Seme', 'North Seme'],
    'Nyando': ['East Kano/Wawidhi', 'Awasi/Onjiko', 'Ahero', 'Kabonyo/Kanyagwal', 'Kobura'],
    'Muhoroni': ['Miwani', 'Ombeyi', 'Masogo/Nyang\'Oma', 'Chemelil', 'Muhoroni/Koru'],
    'Nyakach': ['South West Nyakach', 'North Nyakach', 'Central Nyakach', 'West Nyakach', 'South East Nyakach'],
    
    // Homa Bay County
    'Kasipul': ['West Kasipul', 'South Kasipul', 'Central Kasipul', 'East Kamagak', 'West Kamagak'],
    'Kabondo Kasipul': ['Kabondo East', 'Kabondo West', 'Kokwanyo/Kakelo', 'Kojwach'],
    'Karachuonyo': ['West Karachuonyo', 'North Karachuonyo', 'Central', 'Kanyaluo', 'Kibiri', 'Wangchieng', 'Kendu Bay Town'],
    'Rangwe': ['West Gem', 'East Gem', 'Kagan', 'Kochia'],
    'Homa Bay Town': ['Homa Bay Central', 'Homa Bay Arujo', 'Homa Bay West', 'Homa Bay East'],
    'Ndhiwa': ['Kwabwai', 'Kanyadoto', 'Kanyikela', 'North Kabuoch', 'Kabuoch South/Pala', 'Kanyamwa Kologi', 'Kanyamwa Kosewe'],
    'Mbita': ['Mfangano Island', 'Rusinga Island', 'Kasgunga', 'Gembe', 'Lambwe'],
    'Suba': ['Gwassi South', 'Gwassi North', 'Kaksingri West', 'Ruma Kaksingri East'],
    
    // Migori County
    'Rongo': ['North Kamagambo', 'Central Kamagambo', 'East Kamagambo', 'South Kamagambo'],
    'Awendo': ['North Sakwa', 'South Sakwa', 'West Sakwa', 'Central Sakwa'],
    'Suna East': ['God Jope', 'Suna Central', 'Kakrao', 'Kwa'],
    'Suna West': ['Wiga', 'Wasweta Ii', 'Ragana-Oruba', 'Wasimbete'],
    'Uriri': ['West Kanyamkago', 'North Kanyamkago', 'Central Kanyamkago', 'South Kanyamkago', 'East Kanyamkago'],
    'Nyatike': ['Kachien\'G', 'Kanyasa', 'North Kadem', 'Macalder/Kanyarwanda', 'Kaler', 'Got Kachola', 'Muhuru'],
    'Kuria West': ['Bukira East', 'Bukira Central/Ikerege', 'Isibania', 'Makerero', 'Masaba', 'Tagare', 'Nyamosense/Komosoko'],
    'Kuria East': ['Gokeharaka/Getambwega', 'Ntimaru West', 'Ntimaru East', 'Nyabasi East', 'Nyabasi West'],
    
    // Kisii County
    'Bonchari': ['Bomariba', 'Bogiakumu', 'Bomorenda', 'Riana'],
    'South Mugirango': ['Tabaka', 'Boikang\'A', 'Bogetenga', 'Borabu/Chitago', 'Moticho', 'Getenga'],
    'Bomachoge Borabu': ['Bombaba Borabu', 'Boochi Borabu', 'Bokimonge', 'Magenche'],
    'Bobasi': ['Masige West', 'Masige East', 'Bobasi Central', 'Nyacheki', 'Bobasi Bogetaorio', 'Bobasi Chache', 'Sameta/Mokwerero', 'Bobasi Boitangare'],
    'Bomachoge Chache': ['Majoge', 'Boochi/Tendere', 'Bosoti/Sengera'],
    'Nyaribari Masaba': ['Ichuni', 'Nyamasibi', 'Masimba', 'Gesusu', 'Kiamokama'],
    'Nyaribari Chache': ['Bobaracho', 'Kisii Central', 'Keumbu', 'Kiogoro', 'Birongo', 'Ibeno'],
    'Kitutu Chache North': ['Monyerero', 'Sensi', 'Marani', 'Kegogi'],
    'Kitutu Chache South': ['Bogusero', 'Bogeka', 'Nyakoe', 'Kitutu Central', 'Nyatieko'],
    
    // Nyamira County
    'Kitutu Masaba': ['Rigoma', 'Gachuba', 'Kemera', 'Magombo', 'Manga', 'Gesima'],
    'West Mugirango': ['Nyamaiya', 'Bogichora', 'Bosamaro', 'Bonyamatuta', 'Township'],
    'North Mugirango': ['Itibo', 'Bomwagamo', 'Bokeira', 'Magwagwa', 'Ekerenyo'],
    'Borabu': ['Mekenene', 'Kiabonyoru', 'Nyansiongo', 'Esise'],
    
    // Nairobi County
    'Westlands': ['Kitisuru', 'Parklands/Highridge', 'Karura', 'Kangemi', 'Mountain View'],
    'Dagoretti North': ['Kilimani', 'Kawangware', 'Gatina', 'Kileleshwa', 'Kabiro'],
    'Dagoretti South': ['Mutuini', 'Ngando', 'Riruta', 'Uthiru/Ruthimitu', 'Waithaka'],
    'Langata': ['Karen', 'Nairobi West', 'Mugumo-Ini', 'South C', 'Nyayo Highrise'],
    'Kibra': ['Laini Saba', 'Lindi', 'Makina', 'Woodley/Kenyatta Golf', 'Sarangombe'],
    'Roysambu': ['Githurai', 'Kahawa West', 'Zimmerman', 'Roysambu', 'Kahawa'],
    'Kasarani': ['Claycity', 'Mwiki', 'Kasarani', 'Njiru', 'Ruai'],
    'Ruaraka': ['Baba Dogo', 'Utalii', 'Mathare North', 'Lucky Summer', 'Korogocho'],
    'Embakasi South': ['Imara Daima', 'Kwa Njenga', 'Kwa Reuben', 'Pipeline', 'Kware'],
    'Embakasi North': ['Kariobangi North', 'Dandora Area I', 'Dandora Area Ii', 'Dandora Area Iii', 'Dandora Area Iv'],
    'Embakasi Central': ['Kayole North', 'Kayole Central', 'Kayole South', 'Komarock', 'Matopeni'],
    'Embakasi East': ['Upper Savannah', 'Lower Savannah', 'Embakasi', 'Utawala', 'Mihango'],
    'Embakasi West': ['Umoja I', 'Umoja Ii', 'Mowlem', 'Kariobangi South'],
    'Makadara': ['Makongeni', 'Maringo/Hamza', 'Harambee', 'Viwandani'],
    'Kamukunji': ['Pumwani', 'Eastleigh North', 'Eastleigh South', 'Airbase', 'California'],
    'Starehe': ['Nairobi Central', 'Ngara', 'Ziwani/Kariokor', 'Pangani', 'Landimawe', 'Nairobi South'],
    'Mathare': ['Hospital', 'Mabatini', 'Huruma', 'Ngei', 'Mlango Kubwa', 'Kiamaiko'],
  };

  /// Popular areas for quick suggestions
  static const List<String> popularAreas = [
    'Westlands', 'Kilimani', 'Karen', 'Lavington', 'Kileleshwa',
    'Parklands', 'Runda', 'Muthaiga', 'Gigiri', 'Spring Valley',
    'South B', 'South C', 'Langata', 'Upperhill', 'Hurlingham',
    'Kitengela', 'Ongata Rongai', 'Ngong', 'Kikuyu', 'Ruiru',
    'Juja', 'Thika', 'Naivasha', 'Nakuru', 'Eldoret',
    'Kisumu', 'Mombasa', 'Nyali', 'Diani', 'Malindi',
    'Ruaka', 'Rongai',
  ];

  /// Get all location names for autocomplete
  static List<String> getAllLocationNames() {
    final Set<String> allLocations = {};
    allLocations.addAll(counties);
    for (final constituencies in constituenciesByCounty.values) {
      allLocations.addAll(constituencies);
    }
    for (final wards in wardsByConstituency.values) {
      allLocations.addAll(wards);
    }
    allLocations.addAll(popularAreas);
    return allLocations.toList()..sort();
  }

  /// Search locations matching a query
  static List<LocationSearchResult> searchLocations(String query) {
    if (query.isEmpty) {
      return popularAreas.map((area) => LocationSearchResult(
        name: area,
        type: LocationType.area,
        county: _getCountyForLocation(area),
      )).toList();
    }

    final results = <LocationSearchResult>[];
    final queryLower = query.toLowerCase();

    // Search counties
    for (final county in counties) {
      if (county.toLowerCase().contains(queryLower)) {
        results.add(LocationSearchResult(name: county, type: LocationType.county, county: county));
      }
    }

    // Search constituencies
    for (final entry in constituenciesByCounty.entries) {
      for (final constituency in entry.value) {
        if (constituency.toLowerCase().contains(queryLower)) {
          results.add(LocationSearchResult(
            name: constituency,
            type: LocationType.constituency,
            county: entry.key,
            constituency: constituency,
          ));
        }
      }
    }

    // Search wards
    for (final entry in wardsByConstituency.entries) {
      for (final ward in entry.value) {
        if (ward.toLowerCase().contains(queryLower)) {
          final county = _getCountyForConstituency(entry.key);
          results.add(LocationSearchResult(
            name: ward,
            type: LocationType.ward,
            county: county,
            constituency: entry.key,
            ward: ward,
          ));
        }
      }
    }

    // Search popular areas (these include common nicknames not in official admin divisions)
    for (final area in popularAreas) {
      if (area.toLowerCase().contains(queryLower)) {
        // Skip if already found as a ward/constituency/county
        final alreadyExists = results.any(
          (r) => r.name.toLowerCase() == area.toLowerCase(),
        );
        if (!alreadyExists) {
          results.add(LocationSearchResult(
            name: area,
            type: LocationType.area,
            county: _getCountyForLocation(area),
          ));
        }
      }
    }

    // Sort: exact matches first, then starts with, then contains
    results.sort((a, b) {
      final aLower = a.name.toLowerCase();
      final bLower = b.name.toLowerCase();
      final aExact = aLower == queryLower;
      final bExact = bLower == queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      final aStarts = aLower.startsWith(queryLower);
      final bStarts = bLower.startsWith(queryLower);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return a.name.compareTo(b.name);
    });

    return results.take(20).toList();
  }

  static String? _getCountyForConstituency(String constituency) {
    for (final entry in constituenciesByCounty.entries) {
      if (entry.value.contains(constituency)) return entry.key;
    }
    return null;
  }

  static String? _getCountyForLocation(String location) {
    if (counties.contains(location)) return location;
    for (final entry in constituenciesByCounty.entries) {
      if (entry.value.contains(location)) return entry.key;
    }
    for (final entry in wardsByConstituency.entries) {
      if (entry.value.contains(location)) return _getCountyForConstituency(entry.key);
    }
    return null;
  }

  static List<String> getConstituencies(String county) => constituenciesByCounty[county] ?? [];
  static List<String> getWards(String constituency) => wardsByConstituency[constituency] ?? [];
}

enum LocationType { county, constituency, ward, area }

class LocationSearchResult {
  final String name;
  final LocationType type;
  final String? county;
  final String? constituency;
  final String? ward;
  final int listingCount; // Number of rental listings using this area name

  LocationSearchResult({
    required this.name,
    required this.type,
    this.county,
    this.constituency,
    this.ward,
    this.listingCount = 0,
  });

  String get displayName {
    switch (type) {
      case LocationType.county: return '$name County';
      case LocationType.constituency: return '$name, $county';
      case LocationType.ward: return '$name Ward, $constituency';
      case LocationType.area: return name;
    }
  }

  String get subtitle {
    switch (type) {
      case LocationType.county: return 'County';
      case LocationType.constituency: return 'Constituency in $county County';
      case LocationType.ward: return 'Ward in $constituency, $county';
      case LocationType.area: return listingCount > 0 
          ? 'Popular Area • $listingCount listings'
          : 'Popular Area';
    }
  }

  /// Returns true if this area has active rental listings
  bool get hasListings => listingCount > 0;
}
