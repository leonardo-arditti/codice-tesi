#!/bin/bash

# NB: prima di eseguire questo script creare il database con nome (senza virgolette) "addrtrxgraph", aggiungere gli indici come definito nella tesi e infine mettere i template di codice cypher da eseguire per le analisi e per le importazioni nella cartella "templates"

# CREATE INDEX addressId_index FOR (a:Address) ON (a.addressId);

# NB: gli indirizzi casuali sono salvati in $NEO4J_HOME/import/ tramite procedura apoc.export.csv.query invocata in selectRandomAddresses.cypher, comodo perchè in questo modo possono essere letti direttamente da LOAD CSV (per impostazione predefinita Neo4j legge file solo da $NEO4J_HOME/import)

CHUNKS_DIR="$NEO4J_HOME/import/chunks"
DATABASE_NAME="addrtrxgraph"
DATABASE_USERNAME="yourUsername" # Da cambiare con il proprio username
DATABASE_PASSWORD="yourPassword" # Da cambiare con la propria password
DATABASE_BOLT_ADDRESS="yourBoltAddress" # Da cambiare con il proprio indirizzo bolt
QUERY_TEMPLATE_PATH="./templates/addrtrx.cypher"
SELECT_RANDOM_ADDRESSES_QUERY_PATH="./templates/selectRandomAddresses.cypher"
ANALYSIS_QUERIES_DIR="./templates/analysis_templates"

BASE_DIR="./chunk_results"

# Creazione della cartella base per i risultati se non esiste
mkdir -p "$BASE_DIR"

# Opzionale: definizione dell'intervallo di chunk da considerare
START_CHUNK=${1:-1} # Default è 1 se non specificato
END_CHUNK=${2:-$(ls -1 "$CHUNKS_DIR"/* | wc -l)} # Default è il numero totale di file se non specificato

file_counter=1
total_files=$(($END_CHUNK - $START_CHUNK + 1))

for chunk_file in $(ls $CHUNKS_DIR | sort -V | sed -n "${START_CHUNK},${END_CHUNK}p"); do
  echo ">> Elaborazione del file $chunk_file [file n.$file_counter/$total_files]"
  
  chunk_basename=$(basename "$chunk_file")
  CSV_PATH="file:///chunks/$chunk_basename"
  
  # Estrai l'ultimo blockId per creare il nome della cartella relativa a questo chunk
  last_block_id=$(echo $chunk_basename | awk -F'[_.]' '{print $(NF-1)}')
  
  # Creazione della cartella specifica per questo chunk
  CHUNK_DIR="$BASE_DIR/chunk_${file_counter}_blockId_${last_block_id}"
  mkdir -p "$CHUNK_DIR"
  
  # Preparazione e esecuzione della query Cypher di importazione
  sed "s|{{CSV_PATH}}|$CSV_PATH|g" "$QUERY_TEMPLATE_PATH" > "$CHUNK_DIR/query_temp.cypher"
  cat "$CHUNK_DIR/query_temp.cypher" | $NEO4J_HOME/bin/cypher-shell -d "$DATABASE_NAME" -u "$DATABASE_USERNAME" -p "$DATABASE_PASSWORD" -a "$DATABASE_BOLT_ADDRESS" > "$CHUNK_DIR/risultati_import_chunk_${file_counter}_blockId_${last_block_id}.txt"
  # Rimozione query temporanea per importare chunk_${file_counter}_blockId_${last_block_id}.txt in Neo4j
  rm "$CHUNK_DIR/query_temp.cypher"
  
  # Checkpoint per rendere persistenti sul disco le modifiche effettuate al grafo
  echo "CALL db.checkpoint();" | $NEO4J_HOME/bin/cypher-shell -d "$DATABASE_NAME" -u "$DATABASE_USERNAME" -p "$DATABASE_PASSWORD" -a "$DATABASE_BOLT_ADDRESS"
  # Registrazione della memoria totale usata da Neo4j dopo aver importato il chunk n.$file_counter
  echo "Registrazione dell'uso della memoria per $DATABASE_NAME dopo aver importato $chunk_basename"
  mem_usage_file="$CHUNK_DIR/memoriaTotaleDB_finoA_${file_counter}_blockId_${last_block_id}.txt"
  du -hc $NEO4J_HOME/data/databases/$DATABASE_NAME/*store.db* > "$mem_usage_file"
  echo "Seleziono indirizzi casuali"
  RANDOM_ADDRESSES_FILE="randomAddresses_up_to_chunk_${file_counter}_blockId_${last_block_id}.txt"
  sed "s|randomAddresses_chunk_x.txt|$RANDOM_ADDRESSES_FILE|g" "$SELECT_RANDOM_ADDRESSES_QUERY_PATH" > "$CHUNK_DIR/select_random_addresses_temp.cypher"
  cat "$CHUNK_DIR/select_random_addresses_temp.cypher" | $NEO4J_HOME/bin/cypher-shell -d "$DATABASE_NAME" -u "$DATABASE_USERNAME" -p "$DATABASE_PASSWORD" -a "$DATABASE_BOLT_ADDRESS"
  # Rimozione query temporanea per selezionare indirizzi casuali
  rm "$CHUNK_DIR/select_random_addresses_temp.cypher"

  echo "Inizio query di analisi"
  for analysis_query_file in "$ANALYSIS_QUERIES_DIR"/*; do
    analysis_basename=$(basename "$analysis_query_file" .cypher)
    echo "Eseguo: $analysis_basename"
    
    sed "s|randomAddresses_chunk_x.txt|$RANDOM_ADDRESSES_FILE|g" "$analysis_query_file" > "$CHUNK_DIR/temp_${analysis_basename}.cypher"
    cat "$CHUNK_DIR/temp_${analysis_basename}.cypher" | $NEO4J_HOME/bin/cypher-shell -d "$DATABASE_NAME" -u "$DATABASE_USERNAME" -p "$DATABASE_PASSWORD" -a "$DATABASE_BOLT_ADDRESS" --format=verbose > "$CHUNK_DIR/${analysis_basename}_up_to_chunk_${file_counter}_blockId_${last_block_id}.txt"
    # --format=verbose è necessario per registrare il tempo di esecuzione, quando si usa il reindirizzamento dell'output di una query su file si ha --format plain e viene omesso il tempo di esecuzione
	
	  # Pulizia del file temporaneo della i-esima query di analisi
    rm "$CHUNK_DIR/temp_${analysis_basename}.cypher"
  done
  echo "Query di analisi concluse"

  echo "Elaborazione del file $chunk_file completata."
  
  ((file_counter++))
done

echo "Elaborazione completata per tutti i chunk."