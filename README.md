# Wave-Player

En lille browser-app hvor du kan indlæse en WAV-fil og spille den via et virtuelt klaviatur med 88 tangenter.

## Sådan bruges den

1. Åbn `index.html` i din browser.
2. Vælg en WAV-fil med filvælgeren.
3. Vælg den tangent, som prøven er optaget på, som grundtone.
4. Spil på klaviaturet nederst i appen.

Appen bruger Web Audio API'et til at afspille prøven uden time-stretching. Der anvendes en kort ind- og udfasning for at undgå kliklyde ved afspilning.
