Nume: Lăzăroiu Lucas
Grupă: 341C5

# Tema 2

Organizare
-
Scopul temei este simularea participarii ca si miner intr-un blockchain. Acest lucru presupune gasirea unei valori intregi nonce, cu ajutorul careia se genereaza un nou block hash mai mic decat o anumita dificultate (i.e. un anumit numar de zero-uri consecutive ca si prefix al hash-ului)

* Pe host se pornesc suficiente thread-uri CUDA pentru a verifica toate numerele de la 1 la MAX_NONCE. Block_size-ul folosit este 256, dat fiind faptul ca este un multiplu de 32 (warp size). Alte motive pentru care am ales aceasta valoare sunt pentru a maximiza occupancy si pentru ca am observat ca se foloseste in majoritatea laboratoarelor de ASC la partea de GPU.
* Functia findNonce din gpu_miner.cu calculeaza potentialul block_hash folosind nonce-ul corespunzator index-ului si verifica daca indeplineste conditia de dificultate. Se fac si 3 verificari pentru a salva timpul de executie in cazul in care nonce-ul a fost deja gasit de alt thread astfel:
  - o verificare inainte de calcularea efectiva a block_hash-ului (i.e. aplicarea functiei sha256).
  - inca o verificare inainte de a compara cu dificultatea.
  - o ultima verificare la apelarea functiei atomicCAS (compare and swap). Ca si side effect nonce-ul rezultat va fi intotdeauna primul gasit, depinde de cum gestioneaza scheduler-ul thread-urile.
* Consider ca tema este foarte utila, deoarece face introducerea in cateva concepte mai nișate, dar relevante in orice caz: blockchain, programare pe GPU. De asemenea, se face si o aprofundare pe partea de multithreading si comparare a acesteia cu varianta seriala (mai ales la bonus).
* Cred ca implementarea mea este destul de buna, m-am folosit corect de functiile oferite de schelet si am un flow logic al programului, usor de urmarit si cu niste comentarii pertinente.

***In plus:***

* Am folosit clock() in lock de time() in cpu_miner.c pentru o precizie mai buna (de ordinul microsecundelor).
* In arhiva se poate gasi si un mic script inputs_generator.cpp, ce poate fi folosit pentru a genera fisierul de inputs.txt pentru rularea bonusului (se citeste un numar N de la tastatura si se genereaza N tranzactii aleatoare in format human-readable)


Implementare
-
* Tema a fost implementata in intregime: kernel-urile findNonce si merkleTree pentru calcularea top_hash-ului, citirea tranzactiilor din fisierul data/inputs.txt, printarea resultatelor in results.csv, respectiv data/outputs.csv.
* S-a facut si implementarea seriala a calcularii top-hash-ului in cpu_miner.c in vederea analizei comparative.
* Pentru rularea bonusului (i.e. top_hash creat din fisierele data/inputs.txt, nu din cele 4 tranzactii predefinite in schelet), trebuie doar decomentata linia 8 din gpu_miner.cu, respectiv linia 9 din cpu_miner.c.
* Se vor obtine aceleasi rezultate in results.csv, deoarece data/inputs.txt contine deja cele 4 tranzactii predefinite in schelet. Pentru testarea scalabilitatii se poate folosi inputs_generator.cpp pentru generarea fisierului inputs.txt cu diverse volume de date.
* Acest lucru a fost deja facut:

  * Timp calculare 'top_hash' in cadrul Merkle Tree pentru:
      * GPU:
        - 1.000 de tranzactii: 0.07s
        - 10.000 de tranzactii: 0.12s
        - 50.000 de tranzactii: 0.08s
        - 100.000 de tranzactii: 0.09s
        - 250.000 de tranzactii: 0.09s
        - 500.000 de tranzactii: 0.13s
        - 750.000 de tranzactii: 0.16s
        - 1.000.000 de tranzactii: 0.20s
        - 2.500.000 de tranzactii: 0.29s
        - 5.000.000 de tranzactii: OOM :(
      * CPU:
        - 1.000 de tranzactii: 0.01s
        - 10.000 de tranzactii: 0.09s
        - 50.000 de tranzactii: 0.21s
        - 100.000 de tranzactii: 0.42s
        - 250.000 de tranzactii: 1.11s
        - 500.000 de tranzactii: 1.62s
        - 750.000 de tranzactii: 2.48s
        - 1.000.000 de tranzactii: 3.24s
        - 2.500.000 de tranzactii: 9.08s
        - 5.000.000 de tranzactii: 16.37s

  * Pentru ultimul test la GPU fisierul slurm continea urmatorul mesaj:
    * slurmstepd: error: Detected 23 oom-kill event(s)
    in StepId=418752.batch cgroup. Some of your
    processes may have been killed by the cgroup
    out-of-memory handler.
  * Presupun ca ar putea fi de la lansarea prea multor thread-uri ce duce la depasirea memoriei GPU.
* Se poate observa ca pentru valori mici ale lui N (<10.000), timpurile de rulare sunt asemanatoare pe CPU si pe GPU, dar incepand cu 50.000 de tranzactii, se observa un SPEEDUP de 3x, ce creste direct proportional cu N: pentru 2.500.000 de tranzactii acesta ajunge la 30x.
* Intuitiv, pe GPU, se pare ca timpul de executie al kernel-ului merkleTree poate fi chiar neglijabil sub un milion de tranzactii, deoarece timpul total se mentine in jur de 0.1s. Chiar si pentru N > 1.000.000, rata cresterii nu se compara cu cea de pe CPU.
* Tot intuitiv, motivul pentru care CPU-ul se descurca atat de bine pentru N < 10000 este deoarece overhead-ul pentru crearea si gestionarea thread-urilor nu compenseaza inca pentru marimea setului de date.
* In plus, varianta pe CPU este foarte eficienta oricum, deoarece linia 28 'if (idx % (1 << (tree_level + 1)) == 0)' din gpu_miner.cu, ce verifica daca thread-ul curent ar trebui sa acumuleze un rezultat partial, nu mai este necesara in cpu_miner.c. La linia 224 idx se incrementeaza cu 1 << (level + 1). Acest mic artificiu reduce exponential overhead-ul buclei for.
* Oricum, speedup-ul obtinut este inca destul de bun. Presupunerea mea este ca acesta se va opri din crestere pentru valori foarte mari ale lui N (de ordinul zecilor de milioane, cand kernel-ul merkleTree va acapara timpul de executie), poate undeva la 50x sau 100x.

**Dificultăți întâmpinate**

* Initial am folosit un block_size de 1024 pentru findNonce dar astfel nu pornea niciun thread si nonce-ul nu era gasit (nu am investigat foarte mult cauza atunci si momentan nu am o explicatie).
* Stack smashing/segmentation fault cand incercam sa accesez un pointer device in host (ca si argument al cudaMalloc).
* __syncthreads() functioneaza ca o bariera in cadrul unui bloc, nu pe tot grid-ul, deci a fost nevoie de mai multe apeluri merkleTree (pe nivele) din host.
* OOM pentru (presupun) configurarea unui kernel cu 5 milioane de thread-uri (BLOCK_SIZE 256).

Resurse utilizate
-
* Laboratorul 4 pentru intelegerea memoriei device, kernel-urilor si API-ului de CUDA.
* Laboratorul 5 pentru caracteristicile GPU-ului de pe coada xl: dimensiuni grid si dimensiuni block.
* Laboratorul 6 pentru operatii atomice si memorie unificata.
* Laboratorul 7 pentru inspiratie implementare bonus (exercitiul de mergesort).
* https://emn178.github.io/online-tools/sha256.html: testare corectitudine hash.
* https://www.tutorialspoint.com/c_standard_library/c_function_clock.htm: documentatie clock().
* https://stackoverflow.com/questions/27931630/copying-array-of-pointers-into-device-memory-and-back-cuda: rezolvare problema de stack smashing.

Structura Arhivei
-

- root
  - data
    - inputs.txt
  - cpu_miner.c
  - gpu_miner.c
  - inputs_generator.cpp
  - README.md
