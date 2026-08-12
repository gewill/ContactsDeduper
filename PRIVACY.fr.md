# Politique de confidentialité

[简体中文](PRIVACY.md) · [繁體中文](PRIVACY.zh-Hant.md) · [English](PRIVACY.en.md) · [日本語](PRIVACY.ja.md) · [한국어](PRIVACY.ko.md) · [Español](PRIVACY.es.md) · [Français](PRIVACY.fr.md) · [Deutsch](PRIVACY.de.md)

Date d'entrée en vigueur : 10 août 2026

ContactsDeduper est un outil d'organisation de contacts local pour iOS et macOS. Cette politique explique comment l'application accède, utilise et protège les données de contact.

## Données auxquelles l'application accède

Après avoir accordé l'accès aux Contacts, l'application peut lire et modifier les informations de contact suivantes :

- Noms, surnoms, organisations, départements et titres de poste
- Numéros de téléphone, adresses e-mail, URL et adresses postales
- Anniversaires, anniversaires et relations de contact
- Profils sociaux, comptes de messagerie instantanée et images de contact
- Répertoriez et regroupez les noms et les relations d'adhésion dans vos comptes Contacts

Ces informations sont utilisées uniquement pour rechercher des contacts en double, afficher des preuves correspondantes, fusionner des contacts et créer ou restaurer une sauvegarde que vous choisissez explicitement.

## Collecte et transmission

- L'application ne dispose pas de système de compte, de publicité, d'analyse, de télémétrie ou de SDK de suivi tiers.
- L'application ne télécharge pas de données de contact vers le développeur ou tout autre serveur tiers.
- L'application ne nécessite pas de connexion réseau. La configuration du bac à sable macOS désactive par défaut l'accès au réseau sortant.
- Le fait que la synchronisation des contacts via iCloud, Google ou un autre compte soit contrôlé par les paramètres des contacts du système et le fournisseur de compte concerné, et non par l'application.

## Fichiers de sauvegarde

Vous pouvez explicitement exporter des contacts sous forme de fichier JSON. Une sauvegarde peut contenir des numéros de téléphone, des adresses e-mail, des adresses postales, des anniversaires, des relations, des comptes sociaux et des images de contacts sensibles.

- Les fichiers de sauvegarde sont enregistrés à l'emplacement que vous choisissez dans le sélecteur de fichiers système.
- Les fichiers de sauvegarde ne sont pas téléchargés sur les serveurs du développeur.
- Le format de sauvegarde actuel n'est pas crypté. Stockez-le dans un emplacement fiable et ne le partagez pas publiquement et ne le validez pas dans un référentiel Git.
- Lors de l'importation, l'application valide la taille du fichier, la version du format et le nombre de contacts avant d'écrire dans les contacts.

## Modifications et suppression de données

- Les fusions de groupes de contacts uniques et en masse modifient la base de données de contacts du système et suppriment les enregistrements en double sélectionnés pour la suppression.
- La fusion de listes consolide les membres et supprime les listes en double au sein du même compte Contacts ; il ne supprime pas les contacts comme effet secondaire.
- « Supprimer tous les contacts » supprime les contacts actuellement accessibles à l'application.
- Toutes les actions destructrices nécessitent une confirmation explicite.
- L'application ne conserve pas de copie cloud. Exportez une sauvegarde avant de la fusionner ou de la supprimer lorsque cela est possible.

## Contrôles d'autorisation

Vous pouvez révoquer l'accès aux contacts à tout moment dans les paramètres système iOS ou macOS. L'application ne peut pas lire ou modifier les contacts une fois l'accès révoqué.

## Mises à jour de cette politique

Si l'application ajoute des services réseau, des analyses, une synchronisation cloud ou une nouvelle utilisation des données, cette politique sera mise à jour avec le code et la version.

## Contact

Pour les questions de confidentialité, utilisez les [GitHub Issues](https://github.com/gewill/ContactsDeduper/issues) du projet. Ne joignez pas de données de contact réelles ou de fichiers de sauvegarde à un problème.
