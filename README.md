# Clio K4J — app iOS + CarPlay via Now Playing

Port natif Swift/SwiftUI de `huyx69/clio-k4j`. CarPlay sans entitlement,
sans jailbreak, sans compte dev payant, via l'écran "Lecture en cours".

## Pourquoi ce chemin

iOS 27.2 ne laisse plus passer aucun bypass CarPlay (CoreTrust patché depuis
17.0.1, pas de jailbreak dispo A14+ en octobre 2026, DMA/AltStore PAL ne
distribue pas d'entitlements CarPlay). Mais l'écran **Now Playing** de CarPlay,
celui qu'utilisent Spotify, Apple Music, Pocket Casts, s'affiche
**automatiquement** pour toute app iOS qui tient une `AVAudioSession` active
et pousse des `MPNowPlayingInfo`. Aucun entitlement requis.

L'app joue un silence 44.1 kHz en boucle, pousse chaque seconde titre/artiste/
album avec les mesures OBD, et une **pochette 1024×1024 régénérée** avec un
tableau de bord custom (arc de régime, hero conso, tuiles eau/batterie/moyenne).

Sur CarPlay : "Clio K4J" apparaît dans la grille, à côté de Spotify. Tu l'ouvres,
le K50 affiche la pochette en grand = ton dashboard live. Les boutons
suivant/précédent du volant basculent entre vues (prévu).

## Fonctions

- **Phone — Route** : conso instantanée (speed density), régime, eau,
  batterie, admission, papillon, charge, air, avance, O2, STFT/LTFT, débit.
- **Phone — Diag** : lecture/effacement codes défaut (modes 03, 07, 04).
- **Phone — Pleins** : calibration auto de la conso sur litres de pompe.
- **Phone — Trajets** : historique, courbe vitesse/régime/conso, export CSV, backup JSON.
- **CarPlay** : écran Lecture en cours = tableau de bord 1024×1024 avec
  conso instantanée en gros, régime en arc, 4 tuiles (moyenne, vitesse, eau,
  batterie). Titre/artiste scrollent les détails.

OBD-II via CoreBluetooth. Protocoles ELM327 testés dans l'ordre
`ATSP0 → 5 → 4 → 3` pour la ligne K du K4J (Clio 2 phase 2).

## Install sur iOS 27.2 — SideStore (gratuit)

Pas besoin du 99 $/an d'Apple. Il te faut :

1. **SideStore** installé sur l'iPhone — guide officiel `https://sidestore.io`.
   Signé une fois avec ton Apple ID gratuit, SideStore re-signe l'IPA tous les
   7 jours automatiquement en Wi-Fi via **JitterbugPair** (y'a un setup
   initial sur ordi).

2. Télécharge `ClioK4J.ipa` depuis les Actions de ce repo (onglet *Actions*
   → dernier run → *Artifacts* → `ClioK4J-ipa`). Si tu crées une Release,
   l'IPA est aussi attachée directement.

3. Ouvre l'IPA depuis Fichiers → *Partager* → SideStore → *Install*. Entre
   ton mot de passe Apple ID une fois.

4. Dans la Clio : branche l'iPhone en USB au K50 (ou connexion CarPlay sans fil).
   La grille CarPlay montre tes apps habituelles — l'app **n'apparaît pas**
   dans la grille (pas d'entitlement CarPlay driving-task).

5. Dans l'app sur l'iPhone : *Route* → *Connecter le boîtier* → choisis
   OBDBLE → attends que ça passe au vert. L'app passe en mode audio actif.

6. Sur l'écran CarPlay du K50 : va dans *Lecture en cours* (ou **Musique** →
   source → "Clio K4J"). Le dashboard s'affiche. Verrouille l'iPhone,
   roule, les valeurs se mettent à jour.

Limite : la pochette CarPlay se rafraîchit ~2×/seconde (lissage iOS).
Les champs texte (titre/artiste) tournent avec les mesures.

## Pipeline de build (zéro Mac requis)

1. Push ce dossier sur un repo GitHub.
2. Actions → `Build unsigned IPA` → attend 3 min.
3. L'IPA est dans l'artifact du run. SideStore la re-signe à l'install.

## Arborescence

```
ClioK4J-iOS/
├── project.yml                       # XcodeGen spec
├── .github/workflows/build.yml       # CI macOS, IPA ad-hoc signée
└── ClioK4J/
    ├── App/ClioK4JApp.swift          # entry SwiftUI
    ├── Bluetooth/BLETransport.swift  # CoreBluetooth + restoration
    ├── OBD/{ELM327,OBDManager}.swift # moteur ELM + boucle live
    ├── Core/{K4J,Models,Storage}.swift
    ├── NowPlaying/
    │   ├── SilentAudio.swift         # AVAudioEngine silence loop
    │   ├── DashboardRenderer.swift   # pochette 1024×1024 Core Graphics
    │   └── NowPlayingBridge.swift    # MPNowPlayingInfoCenter
    ├── Views/{Root,Route,Diag,Pleins,Trajets,Theme}.swift
    └── Resources/{Info.plist,ClioK4J.entitlements}
```

## Dongles compatibles

Tout dongle ELM327 BLE qui expose notify/write sur FFF0, FFE0, 18F0, FFE5,
AE30, FEE7, ou l'UUID Veepeak E7810A71. Testé mentalement avec OBDBLE,
V-LINK, Veepeak BLE+, VGate iCar Pro BLE.

## Si ça coince

- **CarPlay ne montre pas "Clio K4J" dans Lecture en cours** → l'audio session
  n'est pas active. L'app doit être *lancée et connectée au boîtier* une fois
  avant que la source apparaisse. Après ça elle reste dispo tant que le trajet
  tourne, écran verrouillé compris.
- **Pochette qui ne change pas** → certains head-units cachent la pochette
  tant qu'ils n'ont pas reçu une transition `playbackState`. Le code renvoie
  `playing` à chaque update, mais si le K50 est buggé, appuie une fois sur
  pause/play sur son écran.
- **BLE qui se déconnecte en passant en background** → la section
  `UIBackgroundModes` déclare `bluetooth-central` et `audio`. État et CoreBluetooth
  state restoration gèrent la reprise.
