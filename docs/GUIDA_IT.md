# Anima 0.5.6 — guida


## Aggiornamento 0.5.6 — blocco Grid al caricamento

Sostituisci soltanto `dust/code/anima/` con la cartella di questo archivio.
Conserva `dust/data/anima/`: i doodle e i PSET già salvati restano utilizzabili.
Esci prima dalla vecchia versione. Se la Grid è già rimasta in uno stato
incoerente, scollegala e ricollegala una volta, poi avvia la nuova Anima da
SELECT e richiama il doodle che provocava il problema.

Il caricamento e il richiamo snapshot ora inviano un solo aggiornamento
completo, evitando la raffica di frame durante la lettura dei parametri.
Il cambio script rilascia esplicitamente il callback della Grid.
Non cambiano le tre pagine, le pressioni, le combinazioni di tasti o il playback.
La modalità `COMPOSITION > playback` scelta e salvata rimane valida.

Anima aggiunge alla base Animator 2 0.4.3 LFO per traccia, freeze e undo/redo. La suite locale copre il comportamento software; verifica comunque il tuo setup hardware prima di usarla dal vivo.

## Installazione e doodle precedenti

1. Estrai lo ZIP e copia la cartella **anima** dentro `dust/code/` tramite Maiden. Il file principale deve risultare `dust/code/anima/anima.lua`.
2. Se aggiorni una versione precedente di anima, sostituisci soltanto `dust/code/anima/` e conserva `dust/data/anima/`. Lascia installato Animator 2 0.4.3 e conserva anche `dust/data/animator2/`.
3. Carica **anima** dal menu SELECT.
4. In PARAMETERS > EDIT > SAVE/LOAD, scegli **load Animator 2 doodle** per aprire un tuo salvataggio precedente. Il relativo `.pset` deve essere accanto al `.doodle`.
5. Salva dal menu **save doodle**: la copia verrà scritta in `dust/data/anima/`. La coppia di file originale resta nella cartella di Animator 2.

Il formato include configurazione e attivazione degli LFO per tutti gli snapshot. Nei vecchi doodle i nuovi LFO partono spenti. Le assegnazioni n.b., MIDI e Crow restano quelle salvate. I parametri sonori delle voci n.b. rimangono condivisi fra gli snapshot.

## Importare un doodle dell’Animator originale

In EDIT > SAVE/LOAD trovi ora **load Animator original**, che apre `dust/data/animator/`. Il `.pset` deve essere accanto al `.doodle`, con lo stesso nome. Salvando dopo l’importazione, Anima crea la propria coppia di file senza modificare la sorgente.

L’importazione recupera le linee e gli snapshot e usa i rate e le intersezioni registrati negli array dello snapshot, anche quando le vecchie copie interne delle tracce sono state sovrascritte dal loader di Animator. Le estensioni di Anima partono neutre: direzione avanti, niente mute/solo, chance e ratchet spenti, trasposizione aggiuntiva zero, LFO per traccia spenti e senza destinazioni.

Il progetto importato usa **EDIT > COMPOSITION > playback = Animator original**. Sullo schermo compare `ORIG`. Questa modalità conserva:

- i divisori esatti, compresi **/5 e /7**;
- l’ottava cumulativa e il mute condiviso dell’intero incrocio;
- reset, canali, soppressione delle note duplicate e limite note originali;
- gli intervalli originali di velocity e durata casuale delle note;
- il rilascio originale delle note, anche quando si sovrappongono.

I sette pad rate della Grid rimangono quelli concordati. `/5` e `/7` sono disponibili in EDIT e leggibili sullo schermo; con questi valori nessuno dei sette pad indica il rate selezionato.

Per utilizzare gli LFO per traccia, chance/ratchet e le nuove risposte alle intersezioni, scegli **playback = anima**. Questo cambia il comportamento delle intersezioni e l’articolazione: per il confronto fedele mantieni `Animator original`. I controlli velocity/durata per traccia tornano a essere usati nel playback Anima; in modalità originale si usano gli intervalli recuperati dal vecchio `.pset`.

Il synth resta **MollyThePoly**. Il suo timbro e gli effetti globali vengono letti dal `.pset`, condivisi dall’intero doodle. Un solo `.doodle` non contiene il timbro. Tempo e sorgente clock possono essere recuperati soltanto se erano effettivamente presenti nel salvataggio.

## Pagine Grid

Tieni premuto l'angolo **16,8** e scegli:

- **13,8:** Canvas;
- **14,8:** Lines;
- **15,8:** Intersections.

Rilascia i tasti. L'angolo da solo non cambia pagina. Quando lo tieni premuto, i tre selettori hanno precedenza su undo e sui controlli della traccia 8.

Ultima riga della **Canvas**:

| Pad | Funzione |
| --- | --- |
| 1–8 | Snapshot |
| 9 | Vuoto |
| 10–11 | Due sequenze di richiami snapshot |
| 12 | Vuoto |
| 13 | Undo |
| 14 | Vuoto |
| 15 | ALT |
| 16 | Navigazione pagine |

Per sovrascrivere uno snapshot: **tieni ALT (15,8) e premi il suo pad**. Salva poi il doodle per conservarlo su disco.

I due pattern registrano ordine e intervalli fra i richiami snapshot: premi un pattern vuoto, richiama gli snapshot, poi premi di nuovo il pattern per terminare la registrazione e avviare il ciclo. I tap successivi fermano/riavviano. I vecchi slot 3–4 vengono conservati nei dati importati ma non sono accessibili sulla nuova Grid.

## Undo e redo

Sulla Canvas, premi **13,8** per annullare. **ALT + 13,8** ripristina la modifica annullata. Il pad è illuminato quando è disponibile un'operazione nella direzione scelta.

La cronologia contiene fino a 16 modifiche manuali: creazione/cancellazione di linee, step attivati/disattivati, clear e spostamenti. Un movimento continuato dell'encoder viene raggruppato. Clock e LFO non aggiungono operazioni. Il recupero di una linea cancellata ne ripristina anche le assegnazioni; sulle tracce rimaste vengono conservati gli eventuali cambiamenti successivi fatti nel menu.

Richiamare uno snapshot o caricare un doodle azzera la cronologia. Undo non recupera una sovrascrittura dello snapshot né modifica i timbri n.b. La cronologia dura soltanto per la sessione corrente.

## Lines, pagina 2

Ogni riga corrisponde alla sua traccia:

| Colonna | Funzione |
| --- | --- |
| 1 | Tap mute; pressione lunga solo |
| 2–5 | Avanti, indietro, pendolo, casuale |
| 6 | Tap ratchet; pressione lunga freeze del suo valore modulato |
| 7 | Tap probabilità; pressione lunga freeze del suo valore modulato |
| 8 | Separatore |
| 9–15 | ×2, ×1, ÷2, ÷3, ÷4, ÷6, ÷8 |

Sotto il titolo `LINES` lo schermo ha cinque righe:

1. Movimento e rate corrente. `MUTE` e `SOLO` compaiono soltanto quando attivi.
2. Uscita della traccia; per n.b. compare anche la voce selezionata, per esempio `n.b.: fluid 1` o `n.b. + MIDI: fluid 1`.
3. Probabilità con origine `BASE`, `LFO` o `HOLD`, ed eventuale `off`.
4. Ratchet con origine `BASE`, `LFO` o `HOLD`, ed eventuale `off` / `INT`.
5. In grigio, soltanto le altre destinazioni LFO assegnate alla traccia: **O** = ottava, **T** = trasposizione in semitoni, **L** = durata della nota in millisecondi, **V** = velocity. Esempio: `O+1 T-12 L120 V96`. Un asterisco segnala un valore congelato, per esempio `O+1*`. Se non ci sono queste destinazioni attive, la riga resta vuota.

I nomi delle voci troppo lunghi sono abbreviati con `...` per rimanere nello schermo.

La pressione lunga dura circa **450 ms**, come il solo. Blocca/sblocca il valore e rimane attiva dopo il rilascio. Il tap mantiene il comportamento precedente. Una pressione lunga non esegue anche il tap. Il freeze scatta al raggiungimento dei 450 ms e conserva il valore dell’ultimo step campionato. Non attiva da solo probabilità o ratchet: i loro interruttori restano separati. Il retrigger alle intersezioni ha invece un’attivazione indipendente, spiegata sotto.

## Intersections, pagina 3

| Colonne | Funzione |
| --- | --- |
| 1–5 | Ottava su, ottava giù, quinta aggiunta, triade, accordo di settima |
| 6 | Separatore spento |
| 7–12 | Mute, retrigger, reverse, reset self, reset others, reset all |
| 13 | Vuoto |
| **14** | **Tap: LFO della traccia on/off. Pressione lunga: freeze di tutte le sue destinazioni** |
| 15 | Tieni premuto per il disegno della singola traccia sullo schermo Norns |

I pad disponibili sono tenui, l'azione selezionata è luminosa. Premi di nuovo un'azione selezionata per disattivarla: non c'è un tasto “none”. Le righe vuote restano spente. **Attivo: luminosità piena e fissa**, come gli altri pad selezionati. **Freeze: lampeggio netto acceso/spento, due volte al secondo**, indipendente dal clock e presente anche in stop. Disattivato senza freeze: tenue. Il lampeggio segnala un valore congelato anche se il suo utilizzo è disattivato; lo schermo in quel caso mostra `off`. Il pad LFO 14 lampeggia quando almeno una destinazione della traccia è congelata.

L'anteprima sul tasto 15 mantiene visibile il disegno durante il play mentre le intersezioni restano modificabili sulla Grid. E1 seleziona la traccia, E2/E3 la spostano. Sulla Canvas E2/E3 spostano tutte le linee.

Le ultime righe dello schermo mostrano ora informazioni della traccia selezionata, senza i promemoria `pad 14` e `hold 15`:

- `LFO ON`, `LFO off`, oppure `LFO HOLD 1/2`: una destinazione congelata su due assegnate. Il conteggio riguarda parametri distinti, non il numero di oscillatori.
- Una riga come `/3  P75%  R2`: rate, probabilità e ratchet correnti dell’LFO, oppure i valori di base se non modulati. `Poff` e `Roff` indicano controlli disattivati; `R2 int` indica retrigger soltanto alle intersezioni, con due ripetizioni.
- `LFO ON no targets` segnala master acceso ma nessuna destinazione attiva. Una pressione lunga in questo stato non crea un falso freeze.

In entrambe le pagine i numeri seguono l’LFO **in tempo reale**, con un aggiornamento visivo di circa 10 volte al secondo, indipendente dal rate della traccia. I valori congelati restano fermi mentre gli altri continuano a cambiare. Gli LFO in secondi liberi continuano a essere visibili anche in stop; quelli sincronizzati seguono il clock Norns quando avanza.

Le letture mostrano il punto corrente dell’onda; le note conservano invece il campionamento ai confini degli step. Con rate lenti il valore visibile può quindi anticipare quello della prossima nota. Il freeze continua a bloccare il valore dell’ultimo step campionato, così conserva l’articolazione ascoltata. L’aggiornamento del display non altera le note, la probabilità o il lampeggio Grid.

## Configurare gli LFO

In EDIT trovi una sola sezione **LFO**, che riunisce tutti gli oscillatori. In alto scegli:

- **section = general LFO:** i due LFO originali che muovono tutte le linee su X/Y;
- **section = track 1 … track 8:** gli LFO della singola traccia;
- **oscillator = LFO 1 oppure LFO 2:** l'oscillatore da configurare.

Il menu mostra solo i controlli della scelta corrente. Cambiare sezione o oscillatore non interrompe e non modifica gli altri LFO. I gruppi TRACK 1–8 mantengono i parametri delle tracce, senza ulteriori gruppi LFO nell'elenco principale. Quando scegli una traccia, trovi:

- **LFO master:** stesso interruttore del pad 14 della pagina 3;
- due LFO indipendenti, ciascuno con il proprio `enabled`;
- forma: sine, triangle, ramp up, ramp down, square, sample & hold;
- tempo: `clock beats` oppure `free seconds`;
- durata del ciclo in beat oppure secondi;
- due destinazioni per LFO, con limiti Min/Max indipendenti.

Le destinazioni sono probabilità, velocity, durata in ms, rate, ottava, trasposizione in semitoni e numero di ratchet. **Ratchet/retrig va da 0 a 4:** quando è attivo, 0 è una pausa, 1 una nota singola, 2–4 il numero di ripetizioni. Lo zero è disponibile anche nei limiti Min/Max dell'LFO. Vale anche per l'azione retrigger delle intersezioni. La linea continua ad avanzare durante le pause. Se il ratchet è disattivato, lo step suona normalmente anche con il valore memorizzato a zero. Per il rate i limiti mostrano direttamente le divisioni musicali. L'ottava è uno spostamento aggiuntivo rispetto alla trasposizione della traccia.

### Ratchet: pad, valore manuale e LFO

Questa tabella assume che non sia attiva l’azione `retrigger` delle intersezioni e che un LFO acceso sia effettivamente assegnato a `ratchet repeats`:

| Pad ratchet (pagina 2) | LFO sul ratchet | Risultato |
| --- | --- | --- |
| Spento | Spento | Una nota normale, senza ratchet |
| Acceso | Spento | Usa `ratchet repeats` di EDIT > TRACK |
| Acceso | Acceso | Usa il valore LFO tra Min e Max, sostituendo il valore manuale |
| Spento | Acceso | Una nota normale: l’LFO non accende il ratchet |

Esempio: EDIT ratchet = 3, LFO Min 1 / Max 4. Con pad acceso e LFO attivo si usano 1–4 ripetizioni, **non 3 più il valore LFO**. Spegnendo il master LFO o disabilitando l’ultima assegnazione al ratchet si torna al 3 manuale. Con Min 0 si introducono pause. Il freeze blocca il numero campionato finché non viene liberato; non spegne il master.

**Eccezione esplicita: `retrigger` della pagina 3 è un’azione indipendente.** All’incrocio usa lo stesso numero di ripetizioni (manuale, modulato o congelato) anche con il ratchet continuo della pagina 2 spento. Per escludere entrambe le forme di ratchet spegni il pad della pagina 2 e deseleziona `retrigger` nella pagina 3. Se il pad è acceso, l’incrocio non somma una seconda raffica: usa una volta il numero corrente.

### Chance sulle singole ripetizioni

Con chance e ratchet attivi, la probabilità viene valutata **separatamente per ogni attacco della raffica**, incluso il primo. Un primo attacco saltato non annulla quelli successivi. Esempio: ratchet 4, chance 50% → possono suonare da zero a quattro attacchi, mediamente due su molte raffiche. I posti saltati restano silenziosi: il ritmo non viene compresso e le note successive mantengono la propria posizione.

- Chance disattivata: passano tutte le ripetizioni.
- Chance 0%: nessun attacco. Chance 100%: tutti gli attacchi.
- Senza ratchet: resta la normale decisione di probabilità per lo step.
- Vale anche per il retrigger delle intersezioni, con il pad ratchet continuo spento.
- Ogni attacco di un accordo condivide una sola decisione per tutte le sue note. Anche le due uscite delle combo, per esempio n.b. + MIDI, passano o saltano insieme.

Se la chance è modulata, si usa la percentuale campionata **all’inizio dello step**, con una nuova estrazione a ogni ripetizione. La percentuale non viene ricampionata dall’LFO nel mezzo della raffica. Cambi successivi a EDIT, master LFO o freeze valgono per gli step seguenti. Congelare la chance blocca la percentuale, mentre gli esiti restano casuali.

Le intersezioni vengono risolte all’inizio dello step: con ratchet/retrigger attivo e chance fra 1 e 99%, la linea partecipa all’incrocio e la probabilità filtra poi gli attacchi. Le ripetizioni saltate non annullano retroattivamente le azioni dell’intersezione. Una chance già a 0% esclude invece la linea prima dell’incrocio, senza occupare il limite note.

I due LFO possono controllare fino a quattro parametri. Se assegni più volte la stessa destinazione, prevale l'ultima assegnazione nell'ordine del menu. Per iniziare conviene assegnare destinazioni diverse.

In un nuovo progetto LFO 1 è predisposto come enabled, LFO 2 è disabled, le destinazioni sono tutte `none` e il master è off. Il solo master on non produce variazioni finché non scegli una destinazione.

### Prima prova: probabilità e ratchet

1. Crea una linea con step attivi.
2. In EDIT > LFO scegli `section = track 1`, `oscillator = LFO 1`, poi `shape = triangle`, `time = clock beats`, `cycle beats = 8`.
3. Imposta target 1 su `probability %`, Min 20 e Max 100.
4. Imposta target 2 su `ratchet repeats`, Min 0 e Max 4: il ciclo comprenderà anche step silenziosi. Se vuoi evitare pause, usa Min 1.
5. Nella pagina 2 attiva probabilità e ratchet sulla traccia 1.
6. Nella pagina 3 premi **14,1** per attivare la modulazione.
7. Nella pagina 2 tieni premuto il pad probabilità **7,1**: la probabilità si blocca, mentre il ratchet continua a muoversi. Un'altra pressione lunga riprende la probabilità.
8. Nella pagina 3 una pressione lunga su **14,1** congela tutte le destinazioni; ripetila per riprenderle. Un tap spegne la modulazione e torna ai valori di base.

Per provare rate e ottava, seleziona `oscillator = LFO 2` nella stessa sezione della traccia e imposta enabled, target 1 rate con intervallo ×1–÷8, target 2 octave fra −1 e +1. Usa un ciclo diverso per ottenere movimenti indipendenti.

### Cosa viene congelato e salvato

Il freeze conserva il valore campionato per la traccia; non ferma le altre destinazioni. Il freeze locale e quello generale agiscono sullo stesso blocco per parametro: puoi liberare il ratchet dal suo pad anche dopo averlo congelato con il pad 14. Se soltanto alcune destinazioni sono congelate, una pressione lunga su 14 congela anche le rimanenti senza cambiare quelle già bloccate; quando sono tutte congelate, una pressione lunga su 14 le libera tutte. Non vengono mai congelati parametri non assegnati.

Rimuovere l’ultima assegnazione attiva a un parametro ne libera il freeze, anche in stop; riassegnarlo non riattiva il vecchio blocco. Cambiare Min/Max mentre è congelato lascia il valore bloccato finché non lo liberi. Il freeze della probabilità conserva la percentuale, non una sequenza di esiti: a 50% ogni step continua ad avere una nuova decisione casuale. Gli oscillatori continuano dietro al freeze: riprendendoli si rientra nella fase corrente. I cicli sincronizzati seguono la posizione del clock Norns, quelli liberi il tempo trascorso del sistema.

I valori musicali vengono campionati ai confini degli step. La divisione rimane fissa per un intero intervallo e ogni raffica di ratchet mantiene la propria articolazione. Perciò un'attivazione o un cambio di parametro può attendere la fine dell'intervallo in corso.

Gli LFO non sovrascrivono i valori manuali. Master off ripristina quelli di base dagli step successivi. Gli snapshot salvano configurazione, intervalli e interruttori LFO. Il freeze è temporaneo: richiamo snapshot, caricamento e modifiche strutturali alle linee lo azzerano. Non viene salvato come timbro o nuovo valore di base.

I due LFO globali X/Y dell'Animator precedente sono nella stessa sezione EDIT > LFO: scegli `section = general LFO` e poi LFO 1 oppure LFO 2. La scelta visualizzata nel menu non viene richiamata dai doodle; vengono invece conservate tutte le configurazioni degli oscillatori, anche quelli non visibili. Il richiamo selettivo degli snapshot è rimandato.

## Uscite e prova di compatibilità

Restano disponibili n.b., MIDI, synth interno, le due combinazioni con MIDI, Crow a coppie fisse, `crow cv (original)`, JF ed ER-301. Le uscite mantengono le proprie caratteristiche: per esempio velocity e durata non cambiano l'impulso fisso di Crow originale. Il clock in ingresso su Crow 1 non viene riconfigurato da Anima.

Dopo la prima prova, salva due snapshot con configurazioni LFO diverse, salva il doodle, ricarica lo script e controlla il richiamo. Prova anche undo/redo e la navigazione tenendo premuto un controllo della traccia 8. I test locali coprono questi percorsi con i parametri reali Norns e dispositivi simulati; resta da confermare la risposta del tuo strumento e delle tue voci installate.
