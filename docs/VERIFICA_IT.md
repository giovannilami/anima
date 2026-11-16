# Verifica locale — anima 0.5.6

134 scenari superati con Lua 5.3 e il ParamSet reale Norns.

- 17 snapshot, persistenza di impostazioni e assegnazioni.
- 12 pagine Grid, anteprima, illuminazione, navigazione, aggiornamenti annidati
  e protezione dai callback di uno script precedente.
- 9 playback/intersezioni, incluse pause retrig=0 senza occupare note o voci Crow.
- 4 salvataggi robusti e gestione degli errori di scrittura.
- 10 modulazione: intervalli, campionamento, freeze locale/generale, rimozione
  delle destinazioni, zero e richiamo snapshot.
- 3 menu LFO con il menu EDIT originale Norns.
- 7 undo/redo e gesture.
- 18 simulazioni temporali di freeze, playback, uscite e schermo (dettagli sotto).
- 29 routing/rilascio su destinazioni simulate.
- 2 avvii completi con n.b. simulato presente e assente, incluso cleanup del timer visivo.
- 6 controlli aggiuntivi attraverso l’avvio completo: caricamento di doodle
  a otto tracce, richiami rapidi di snapshot e rilascio della connessione Grid,
  ciascuno con n.b. presente e assente.
- 3 cleanup e gestione dei vecchi timer.
- 1 gestione dei due pattern e conservazione dei vecchi slot.
- 7 confronti delle emissioni Crow con il codice originale Animator.
- 4 importazione originale: divisori esatti, controlli neutri, algoritmo di
  intersezione/articolazione originale e richiamo tra due impulsi.
- 2 importazioni originali attraverso l’avvio completo: salvataggio, ricarica
  e ritorno a un doodle Anima, con n.b. presente e assente.

## Correzione Grid durante il caricamento (0.5.6)

Il log sullo strumento riporta scritture libmonome incomplete e
`Resource temporarily unavailable` durante `pset >> read`. Il test con
ParamSet reale riproduce 280 frame Grid in un solo caricamento quando
cambiano molte impostazioni. Ogni azione parametro poteva pubblicare una
pagina intermedia; un invio USB interrotto può spiegare l’illuminazione
incoerente e la necessità di ricollegare il dispositivo. Il successivo errore
`no entry for arc 6` non dimostra che Anima usasse un Arc.

Doodle e snapshot ora applicano le stesse azioni musicali dentro un
aggiornamento che sospende temporaneamente Grid, schermo e count. Solo
al completamento viene pubblicato un frame, già con lo snapshot selezionato.
Il blocco è annidabile e viene rilasciato anche se un’azione genera errore;
non costituisce un rollback dei parametri in caso di errore. Il cambio script
disattiva i vecchi callback e scollega solo l’handler Grid posseduto da Anima.

Sono stati simulati 40 caricamenti con molti parametri cambiati e 40
richiami alternati degli snapshot 1/8, su otto tracce, sia con n.b. presente
sia assente. Ogni caricamento e ogni pressione snapshot pubblica esattamente
un frame completo; le release mantengono il normale ridisegno. Gli stessi
controlli anti-raffica falliscono sul codice 0.5.5 e passano sulla 0.5.6.
Tutte le coordinate trasmesse sono controllate entro 16×8 e i livelli entro
0–15. Sono verificati anche fine script e recupero del blocco dopo errore.

Questa simulazione misura le chiamate realmente dirette alla Grid dal codice,
non un dispositivo USB fisico. Il ripristino del collegamento dopo le scritture
interrotte e il preset modificato sul Norns richiedono la prova sullo strumento.
Non cambiano layout, gesture, assegnazioni, LFO o regole musicali.

## Difetti riprodotti prima della correzione

Nella 0.5.1 un freeze generale faceva risultare congelata anche la probabilità
non assegnata, il pad locale non liberava il ratchet congelato dal generale,
e un master senza destinazioni segnalava comunque un freeze riuscito.
Le tre riproduzioni falliscono sulla 0.5.1 e passano con la correzione.
Ora c’è un unico valore bloccato per destinazione, condiviso fra i due gesti.

## Simulazioni con tempo virtuale

Si usano Animator, ParamSet, Grid, modulo LFO, coda uscite e UI reali del
progetto. Il tempo, i dispositivi fisici e i timer sono simulati. Le pressioni
attraversano davvero la soglia di 450 ms mentre il playback continua.

| Prova | Esito verificato |
| --- | --- |
| 72 combinazioni: 6 forme × 45/120/240 BPM × x2/x1 × tempo libero/sincronizzato | Il ratchet campionato resta identico durante il freeze, incluso zero; il rilascio non modifica il valore di EDIT |
| Step lento /8 | Si congela il valore dell’ultimo step, diverso dal punto istantaneo dell’onda |
| Freeze ratchet, poi generale, poi rilascio locale | Il ratchet riprende e velocity resta congelata; nessuna priorità nascosta |
| Due LFO sul ratchet | Prevale l’ultima assegnazione; il freeze conserva il risultato finale |
| Coda reale di ripetizioni | Ogni raffica completa emette esattamente tre note quando si congela il valore 3 |
| Pad ratchet on/off, LFO on/off, cambio valore manuale | Il valore LFO sostituisce quello manuale; pad off impedisce il ratchet continuo |
| Retrigger alle intersezioni con pad ratchet off | Resta un’azione indipendente; deselezionarla riporta alla nota singola |
| Probabilità congelata a 50% | La percentuale è fissa, gli esiti restano variabili; spegnendo il controllo passa ogni step |
| Lampeggio a 45 e 240 BPM e in stop | Alternanza 15/0 a 2 Hz; attivo senza freeze = 15; disattivato senza freeze = 2 |
| Canvas e selettore pagine | Il timer visivo non ridisegna queste viste e non introduce sfarfallamento della navigazione |
| Schermo | Cinque righe Lines con uscita/voce, flag solo quando attivi e footer grigio con O/T/L/V; conteggio HOLD e letture pagina 3 |
| Aggiornamento dal timer con playback fermo | I valori cambiano anche senza note o encoder, senza modificare i campioni audio o inviare frame Grid; nessun aggiornamento su Canvas, navigazione o anteprima |
| Freeze durante lettura dal vivo | Valori congelati stabili, altri valori in movimento; resta congelato l’ultimo campione musicale |
| Confronto display aperto/chiuso: 6 forme × 2 modalità temporali | Note, tempi, velocity e successiva estrazione casuale identici, incluso sample & hold |
| Navigazione durante pressione e cambio proprietario dei parametri | Nessun freeze o tap residuo; il timer visivo si chiude senza fermare quello delle uscite |

## Compatibilità originale

Il confronto usa `count()` del checkout originale senza modificarne il
playback. Le sequenze di riferimento vengono costruite applicando gli array
salvati `divs` e `intersects`, per evitare di riprodurre l’errore del vecchio
loader. Vengono confrontati note, canali, velocity, frequenze, note-off,
playhead, contatori e reset per 512 impulsi originali per scena.

La frequenza viene confrontata al microhertz; la coda delle uscite conserva
la propria risoluzione di 5 ms. Le piccole differenze numeriche nella formula
MIDI→Hz non cambiano la nota. Il consumo casuale dell’articolazione coincide.
La verifica sul suono fisico richiede comunque Norns e il motore installato.

I test possono ricevere una coppia `.doodle`/`.pset` esterna e copie convertite
per confrontare progetti senza includere dati personali nel codice o negli
archivi dello script.

## Chance per attacco del ratchet

Otto scenari nuovi verificano la modifica con il playback e la coda reali:

- Su tutte le 10 uscite da internal synth a Crow originale, la sequenza di
  decisioni salta/suona/salta/suona esegue quattro estrazioni e due attacchi.
- Un primo attacco saltato lascia suonare quelli a +1/4 e +3/4 dello step,
  senza comprimere gli intervalli né eliminare l’intera raffica.
- Triadi e combo n.b./internal + MIDI condividono ogni decisione e
  mantengono accordi completi su entrambe le destinazioni.
- Chance 0%, 100% e disattivata mantengono pause, playback completo e bypass.
- Stop della traccia, panic e cleanup cancellano anche le estrazioni future.
- LFO, freeze e modifiche manuali durante una raffica conservano la sua
  percentuale campionata; il successivo step applica il nuovo valore.
- Il retrigger alle intersezioni applica chance per attacco anche con il
  ratchet continuo spento: due triadi passano e due saltano.
- Chance zero non occupa il limite note o l’assegnazione Crow dell’altra linea.

Verificata anche la larghezza delle stringhe più lunghe con il font `norns.ttf`
reale a 8 px: movimento con MUTE/SOLO, uscite combo, probabilità, ratchet,
letture Intersections e tutti e quattro i valori aggiuntivi congelati rientrano
nei 120 px disponibili (massimo misurato: 102 px). I nomi n.b. più lunghi
vengono abbreviati usando le misure del display.

Le 72 combinazioni sono incluse in uno dei 18 scenari temporali, non sommate
al totale di 134. La sintassi di tutti i file Lua viene controllata separatamente.

Queste verifiche non sostituiscono la prova audio, MIDI e Crow sullo strumento.
Le voci n.b. e i dispositivi sono simulati. Il menu EDIT invece è il codice
reale Norns, esercitato con schermo ed encoder simulati.
