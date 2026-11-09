# Vieira-STRIKE — Portal Web & Painel Administrativo

Frontend moderno (Single Page Application - SPA) 100% estático desenvolvido com HTML5, CSS3 e JavaScript puro, sem dependência de Node.js no build.

Pode ser hospedado gratuitamente no **GitHub Pages** e consome a API FastAPI do servidor Vieira-STRIKE.

---

## 🌐 Como Publicar no GitHub Pages

O projeto já inclui um workflow do GitHub Actions em [`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml) que faz o deploy automático sempre que você enviar commits para o GitHub.

### Passo a passo para ativar:

1. Acesse o seu repositório no **GitHub**.
2. Vá em **Settings** > **Pages** (no menu lateral esquerdo).
3. Na seção **Build and deployment**:
   - Em **Source**, selecione **GitHub Actions**.
4. Faça um push no repositório (ou acesse a aba **Actions** e execute o workflow manualmente).
5. Seu site estará no ar no endereço: `https://seu-usuario.github.io/nome-do-repositorio/`

---

## ⚙️ Conectando à API do Servidor

No rodapé da página (ou via `localStorage`), você pode configurar o campo **API Endpoint** apontando para o seu servidor, por exemplo:
- Ambiente de desenvolvimento local: `http://localhost:8000`
- Ambiente de produção: `https://api.seuservidor.com`

> **Importante (CORS):** O backend FastAPI já possui suporte a CORS configurado para aceitar conexões vindas de domínios `https://*.github.io` e `http://localhost:*`.
