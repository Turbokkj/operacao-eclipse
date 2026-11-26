# Operação Eclipse

Projeto Godot 4.3 com exportação Web para Vercel e servidor de salas WebSocket separado.

O arquivo `source_payload.tar.xz.b64` contém o código-fonte do jogo compactado em XZ e codificado em Base64. Ele não inclui os arquivos binários de áudio e texturas: o processo de build os gera a partir dos scripts-fonte. O relatório interno de testes não foi incluído.

A Vercel extrai o código e executa a exportação Web. O serviço em `operacao-eclipse/server/` é independente e precisa de hospedagem persistente para o multiplayer online.
