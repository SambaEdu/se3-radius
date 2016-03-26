#!/bin/sh
# Rédigé par Nicolas Aldegheri le 26/03/2016
# Sous licence GNU

echo "Ce script permet d'intégrer un serveur freeradius dans un réseau se3"
echo "Deux configurations sont possibles :"
echo "      - installer freeradius sur un serveur Debian Jessie dédié"
echo "      - installer freeradius sur un se3 wheezy"
echo "Si l'installation est réalisée sur un serveur Debian Jessié dédié, renseigner au début du script les variables en les adaptant à votre réseau"
echo "Etes-vous sur de vouloir continuer ? o ou n ? :																				"
read REPONSE

if [ "$REPONSE" != "o" ]
then	
	exit 0;
fi

############################################################################################################
# Variables à compléter dans le cas où l'installation est réalisée sur un serveur Debian Jessie dédié
ldap_server=""															# IP du se3
ldap_port="389"															# Port du service ldap sur le se3, par défaut 389
mask_reseau=""															# mettre 16 pour 255.255.0.0 ou 24 pour 255.255.255.0
ldap_base_dn="ou=lyc-demo,ou=ac-versailles,ou=education,o=gouv,c=fr"	# Base DN de l'annuaire LDAP
adminPw=""																# Mot de passe de l'admin de l'annuaire ldap du se3 : à récupérer via l'interface web "setup" du se3
secret_borne_wifi=""													# Secret partagé entre les bornes wifi et le serveur Radius :
																		# à renseigner à l'identique dans le paramétrage WPA2-Enterprise de toutes les bornes wifi du réseau pédagogique
# Fin des variables à renseigner
#############################################################################################################

if [ -e /etc/se3/config_l.cache.sh ]
then
	# L'installation de freeradius est réalisée sur un se3, on récupére directement les variables précédentes dans les fichiers de conf du se3
	. /etc/se3/config_l.cache.sh
	. /etc/se3/config_m.cache.sh
	
	# Par défaut, le secret partagé sera le mot de passe adminse3 (mot de passe de l'administrateur local d'un poste windows ou linux)
	secret_borne_wifi="$xppass"
	
	# Détermination du masque de réseau au format 16 pour 255.255.0.0 ou 24 pour 255.255.255.0
	mask_reseau=$(($(echo "$se3mask" | grep -o "255" | wc -l)*8))
	
fi
																		
apt-get update
apt-get install -y freeradius freeradius-ldap
		

echo "Etape 1 : Paramétrage du module ldap de Freeradius"

#Sauvegarde l'original avant modification 
# cp -n /etc/freeradius/modules/ldap /etc/freeradius/modules/ldap_original

cat <<EOF > "/etc/freeradius/modules/ldap"
ldap {
	server = "$ldap_server"
	port = "$ldap_port"
	identity = "cn=admin,$ldap_base_dn"
	password = "$adminPw"
	basedn = "ou=People,$ldap_base_dn"

	ldap_connections_number = 50
	max_uses = 0
	timeout = 4
	timelimit = 3
	net_timeout = 1

	filter = "(uid=%{%{Stripped-User-Name}:-%{User-Name}})"
	
	tls {
		start_tls = yes
		require_cert = "never"
	}

	dictionary_mapping = \${confdir}/ldap.attrmap
	edir_account_policy_check = no

	groupname_attribute = "cn" 
	groupmembership_attribute = "memberUid" 
	groupmembership_filter = "(memberUid=%{%{Stripped-User-Name}:-%{User-Name}})" 

	keepalive {
		# LDAP_OPT_X_KEEPALIVE_IDLE
		idle = 60

		# LDAP_OPT_X_KEEPALIVE_PROBES
		probes = 3

		# LDAP_OPT_X_KEEPALIVE_INTERVAL
		interval = 3
	}
}
EOF

chmod 550 /etc/freeradius/modules/ldap

echo "Etape 2 : Paramétrage de l'authorisation utilisateur par ldap"

#Sauvegarde l'original avant modification 
# cp -n /etc/freeradius/sites-available/default /etc/freeradius/sites-available/default_original
# cp -n /etc/freeradius/sites-available/inner-tunnel /etc/freeradius/sites-available/inner-tunnel_original

cat <<EOF > /etc/freeradius/sites-available/default
authorize {
	preprocess
	chap
	mschap
	digest
	suffix
	eap {
		ok = return
	}
	files
	ldap
	expiration
	logintime
	pap
}

authenticate {
	Auth-Type PAP {
		pap
	}
	Auth-Type CHAP {
		chap
	}
	Auth-Type MS-CHAP {
		mschap
	}
	digest
	unix
	eap
}

preacct {
	preprocess
	acct_unique
	suffix
	files
}

accounting {
	detail
	exec
	attr_filter.accounting_response
}

session {
	radutmp
}

post-auth {
	exec
	Post-Auth-Type REJECT {
		attr_filter.access_reject
	}
}

pre-proxy {
}

post-proxy {
	eap
}

EOF

cat <<EOF > /etc/freeradius/sites-available/inner-tunnel

server inner-tunnel {

	listen {
       ipaddr = 127.0.0.1
       port = 18120
       type = auth
	}

	authorize {
		chap
		mschap
		suffix
		update control {
	       Proxy-To-Realm := LOCAL
		}
	
		eap {
			ok = return
		}
	
		files
		ldap
		expiration
		logintime
		pap
	}

	authenticate {
		Auth-Type PAP {
			pap
		}

		Auth-Type CHAP {
			chap
		}

		Auth-Type MS-CHAP {
			mschap
		}

		unix
		eap
	}

	session {
		radutmp
	}

	post-auth {
		Post-Auth-Type REJECT {
			attr_filter.access_reject
		}
	}

	pre-proxy {
	}

	post-proxy {
		eap
	}
}
EOF


echo "Etape 3 : Spécificer les groupes d utilisateurs du réseau se3 qui sont authorisés à utiliser le wifi"
echo "Par défaut, seul les utilisateurs des groupes Profs et admins du se3 sont authorisés à utiliser les bornes wifi"

# cp -n /etc/freeradius/users /etc/freeradius/users_original

cat <<EOF > /etc/freeradius/users

DEFAULT Ldap-Group == "cn=Profs,ou=Groups,$ldap_base_dn"
DEFAULT Ldap-Group == "cn=admins,ou=Groups,$ldap_base_dn"
DEFAULT Auth-Type := Reject 

DEFAULT	Framed-Protocol == PPP
	Framed-Protocol = PPP,
	Framed-Compression = Van-Jacobson-TCP-IP

DEFAULT	Hint == "CSLIP"
	Framed-Protocol = SLIP,
	Framed-Compression = Van-Jacobson-TCP-IP

DEFAULT	Hint == "SLIP"
	Framed-Protocol = SLIP

EOF

chown root:freerad /etc/freeradius/users

echo "Etape 4 : Définir peap comme méthode de sécuration eap par défaut"

# cp -n /etc/freeradius/eap.conf /etc/freeradius/eap_original.conf

sed -i -r -e "s/^.*default_eap_type.*$/default_eap_type=peap/" "/etc/freeradius/eap.conf"

echo "Etape 5 : Définir les bornes wifi autorisées à communiquer avec le serveur freeradius"
echo "Par défaut, on autorise toute les bornes connectées au réseau pédagogique (et connaissant le secret partagé ...) à communiquer avec le serveur Radius "

# cp -n /etc/freeradius/clients.conf /etc/freeradius/clients_original.conf

cat <<EOF >/etc/freeradius/clients.conf

# Pour un éventuel débuggage avec radtest :
client localhost {
	ipaddr = 127.0.0.1
	netmask = 32
	secret		= testing123
	require_message_authenticator = no
	shortname	= localhost
	nastype     = other	# localhost isn't usually a NAS...
}

# Pour éviter de renseigner toutes les bornes wifi, on autorise toute borne wifi du réseau péda à communiquer avec le serveur Radius
client pedagogiques {
	ipaddr = $ldap_server
	netmask = $mask_reseau
	secret= $secret_borne_wifi
	require_message_authenticator = no
	shortname = pedagogiques
	nastype = other
}

EOF

echo "Etape 6 : Redémarrage du serveur freeradius"

service freeradius restart

