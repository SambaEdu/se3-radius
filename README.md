# se3-radius

Ce paquet installe et configure le service freeradius pour un serveur SambaEdu Wheezy.

Par défaut :
* L'authentification EAP utilisée est MSCHAP/PEAP et le secret partagé avec les bornes wifi est le mot de passe adminse3 (mot de passe de l'administrateur local d'un client Windows/Linux intégré au se3).
* Toutes les bornes wifi reliées au réseau pédagogique et configurées WPA2-Enterprise avec le secret partagé précédent pourront authentifier et autoriser les utilisateurs d'équipements wifi.
* Seules les utilisateurs du groupe admin et Profs de l'annuaire du se3 sont autorisés à s'authentifier sur les bornes wifi.

Pour présentation plus détaillée de la configuration retenue et appliquée dans ce paquet, se reporter à l'article suivant :
* [Déployer le wifi (WPA2-Enterprise) dans un réseau Se3](http://wiki.dane.ac-versailles.fr/index.php?title=D%C3%A9ployer_le_wifi_%28WPA2-Enterprise%29_dans_un_r%C3%A9seau_Se3)
