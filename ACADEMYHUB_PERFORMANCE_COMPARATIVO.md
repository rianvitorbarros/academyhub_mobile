# AcademyHub Mobile — comparativo parcial de performance

**Data:** 11/10/2026 · **Escopo autorizado:** login e instrumentação do pós-login em desenvolvimento · **Deploy:** nenhum.

## Resumo para decisão

No mesmo build local, ferramenta e perfil de navegador, os campos de login ficaram utilizáveis **0,69 s antes** na abertura fria do Chrome mobile simulado (mediana de 2,93 s para 2,24 s) e **0,68 s antes** na reabertura (1,27 s para 0,59 s). No WebKit simulado, as reduções foram **0,59 s** e **0,67 s**. Em rede limitada a 4 Mb/s e 150 ms, a redução medida foi **1,55 s**, mas a abertura ainda levou **25,57 s**: o JavaScript e o runtime Flutter continuam dominando a transferência inicial.

O login deixou de aguardar 600 ms fixos após a imagem estar pronta. A mesma ilustração foi recomprimida em JPEG de alta qualidade, de 682.524 para 242.019 bytes (−64,5%), sem mudar dimensões ou composição. O número de requisições ficou em 13. O bundle `main.dart.js` **aumentou** ligeiramente com a instrumentação (7.188.573 → 7.191.821 bytes); não houve redução comprovada de trabalho da thread principal na abertura fria.

**Este é um resultado parcial.** O pós-login foi apenas instrumentado. Não há medição autenticada inicial ou posterior, nem validação em PWA instalado no iPhone. O alvo preliminar de 30% para login frio **não foi atingido** no Chrome mobile simulado (23,5%). Não recomendo liberação de produção antes dos ensaios autenticados, do iPhone real e da revisão final.

## 1. Versões, método e comparabilidade

O artefato **antes** é `.tmp-audit-build/`, criado na Etapa 1 a partir do checkout local anterior às correções desta etapa. O artefato **depois** é `.tmp-audit-final/`, ambos gerados com Flutter 3.47.0/Dart 3.13.0, `flutter build web --release --pwa-strategy=none`, `APP_BUILD_ID=audit-20261011` e `APP_NAME=academyhub-mobile-web`. O `version.json` válido do artefato antes foi copiado para o artefato final **somente para o teste local**, evitando um aviso espúrio do build direto; essa cópia não é alteração do código nem deploy. O servidor HTTP local, porta 8123, serviu os dois artefatos de forma sequencial, com a mesma política de ETag/revalidação. Os dois builds também incorporaram alterações locais preexistentes e ainda não commitadas no checkout compartilhado. O commit desta entrega contém apenas nossas mudanças; **sozinho, sem aquele estado local, ele não reproduz byte a byte os artefatos medidos**.

Chrome 155 no Windows e Playwright WebKit 26.0 usaram viewport 390×844, DPR 3 e toque simulado. Cada cenário normal teve 10 aberturas frias em contextos novos e 10 recargas aquecidas nos mesmos contextos. O tempo começa em `page.goto` e termina quando o campo semântico `Username/Email` fica disponível após habilitar a árvore de acessibilidade Flutter. Inclui rede local, inicialização e renderização; a habilitação de semântica é idêntica nos dois artefatos. A mediana usa os dois valores centrais; P95 usa *nearest rank* (10ª observação em n=10); variação é mínimo–máximo.

A rede móvel simulada usou Chrome, download 4 Mb/s, upload 2 Mb/s, 150 ms de latência, 10 execuções válidas para cada artefato. Uma execução anterior teve timeout de navegação e foi repetida nas mesmas condições; os JSON preservam essa falha. O servidor local não aplicou compressão HTTP, portanto seus 8,5–8,9 MB transferidos **não são comparáveis** aos bytes do deploy público da Etapa 1. Nenhuma conta foi usada nesses ensaios. Os resultados do deploy público anterior, de outro commit, não foram tratados como valores “antes” deste comparativo.

## 2. Tempo para login utilizável — mediana, P95 e variação

Todos os tempos estão em milissegundos. Melhoria = `(mediana antes − mediana depois) / mediana antes`.

| Ambiente e cache | Antes: mediana / P95 / variação | Depois: mediana / P95 / variação | Melhoria da mediana |
|---|---:|---:|---:|
| Chrome mobile simulado, frio, n=10 | 2.925 / 4.943 / 2.139–4.943 | 2.239 / 2.290 / 1.339–2.290 | **23,5%** |
| Chrome mobile simulado, aquecido, n=10 | 1.270,5 / 1.686 / 1.236–1.686 | 586,5 / 643 / 547–643 | **53,8%** |
| WebKit Windows simulado, frio, n=10 | 2.168 / 2.538 / 2.077–2.538 | 1.580,5 / 1.812 / 1.532–1.812 | **27,1%** |
| WebKit Windows simulado, aquecido, n=10 | 1.983,5 / 2.066 / 1.625–2.066 | 1.314 / 1.368 / 1.270–1.368 | **33,8%** |
| Chrome, 4 Mb/s e 150 ms, frio, n=10 | 27.117,5 / 27.190 / 26.205–27.190 | 25.566 / 25.651 / 24.620–25.651 | **5,7%** |

```text
Login utilizável, medianas (cada bloco ≈ 0,25 s; rede limitada ≈ 2 s)
Chrome frio       antes ████████████ 2,93 s   depois █████████ 2,24 s
Chrome aquecido   antes █████ 1,27 s          depois ██ 0,59 s
WebKit frio       antes █████████ 2,17 s      depois ██████ 1,58 s
WebKit aquecido   antes ████████ 1,98 s       depois █████ 1,31 s
Rede limitada    antes ██████████████ 27,12 s depois █████████████ 25,57 s
```

**Primeira pintura (FCP) indicativa:** Chrome frio 1.578 → 1.576 ms (P95 3.600 → 1.596); Chrome aquecido 408 → 386 ms (P95 692 → 400). WebKit frio 982 → 990 ms (P95 1.139 → 1.278); WebKit aquecido 704 → 690,5 ms (P95 733 → 707). FCP pode ser o splash do navegador/Flutter; não equivale ao formulário visível. O término do download da imagem no Chrome frio foi 2.002 → 1.989 ms de mediana e na rede limitada 26.213 → 25.190 ms. `responseEnd` não mede decodificação isolada.

## 3. Recursos, requisições e thread principal

| Indicador, mediana | Antes | Depois | Variação |
|---|---:|---:|---:|
| Ilustração de login no build | 682.524 B | 242.019 B | −64,5% |
| `main.dart.js` no build | 7.188.573 B | 7.191.821 B | **+0,05%** |
| Requisições da origem, Chrome frio/aquecido | 13 / 13 | 13 / 13 | 0 |
| Bytes da origem, Chrome frio | 8.935.464 B | 8.498.207 B | −4,9% |
| Bytes da origem, Chrome aquecido | 7.192.755 B | 7.196.003 B | **+0,05%** |
| Bytes da origem, WebKit frio | 8.929.823 B | 8.492.566 B | −4,9% |
| Bytes da origem, WebKit aquecido | 1.728.323 B | 1.287.818 B | −25,5% |
| Soma das *long tasks*, Chrome frio | 591,5 ms (P95 804) | 603,5 ms (P95 813) | **+2,0%** |
| Soma das *long tasks*, Chrome aquecido | 147,5 ms (P95 152) | 143 ms (P95 146) | −3,1% |

O WebKit usado não forneceu entradas `longtask`; zero na coleta significa **métrica indisponível**, não ausência de travamento. Não há amostra válida de memória total do processo, frames perdidos ou INP. LCP/CLS baseados no DOM não descrevem adequadamente todo o conteúdo CanvasKit; a marca do campo utilizável é a alternativa principal. O cabeçalho de `main.dart.js` mudou de `no-store` para `no-cache, must-revalidate` em `web/_headers` e `netlify.toml`: isso permite cache com **revalidação por ETag** sem aceitar bundle desatualizado sem verificar. O servidor local já usava revalidação nos dois artefatos; **não há melhoria medida atribuível a esse cabeçalho em Netlify ou iPhone**. A regra não altera cache de dados escolares.

## 4. Alterações realizadas e causas comprovadas

| Alteração | Evidência e mecanismo | Arquivos |
|---|---|---|
| Remoção da espera fixa de 600 ms depois de `precacheImage` | Espera presente no baseline; campos passaram a surgir antes com imagem já pronta | `lib/screens/loginPage.dart` |
| Proteção para não iniciar a pré-carga novamente em `didChangeDependencies` | O método pode ser chamado mais de uma vez; a guarda evita operações repetidas durante a mesma montagem. Não foi medida frequência anterior em produção | `lib/screens/loginPage.dart` |
| Recompressão JPEG de qualidade 95/MozJPEG | Mesma resolução 1152×912; 440.505 B a menos; PSNR de 43,94 dB contra o JPEG anterior, calculado nos pixels decodificados. Comparação visual abaixo | `lib/assets/imagem_de_login.jpg` |
| Revalidação do bundle JS | A configuração anterior impedia cache HTTP; alteração preparada, ainda sem ensaio de deploy de prévia | `web/_headers`, `netlify.toml` |
| Marcas opt-in de performance | `ACADEMYHUB_PERF_TRACE=true` registra estágios sem IDs, CPF, token, URL ou corpo de resposta; não muda ordem de chamadas | `lib/services/performance_trace.dart`, `lib/providers/auth_provider.dart`, `lib/providers/dashboard_provider.dart`, `lib/screens/loginPage.dart`, `lib/screens/teacher/screen_teacher_dashboard.dart`, `lib/screens/ScreenHomePage.dart` |

As marcas cobrem: toque em Entrar; API de equipe/aluno/responsável; fallback de usuário da equipe; persistência de tokens e sessão; preferências e restauração de sessão; refresh; requisição de métricas da gestão; termos e horários do professor; primeiro frame com conteúdo nos painéis de gestão e professor. Na versão padrão, o rastreio está desligado. Para a homologação, compilar com `--dart-define=ACADEMYHUB_PERF_TRACE=true`, coletar console/Timeline e correlacionar com Network e logs da API. A instrumentação **não fornece dados autenticados por si só**.

## 5. Pós-login, autenticação e navegação

| Indicador solicitado | Antes | Depois | Estado |
|---|---:|---:|---|
| API de autenticação; recuperação/persistência de sessão | Não medido | Não medido | Aguardam contas fictícias e ambiente de homologação |
| “Preparando seu painel”; requisições do dashboard | Não medido | Não medido | Marcas preparadas; nenhuma otimização substancial aplicada |
| Painel visível/interativo; navegação entre Início, Alunos, Turmas e Mais | Não medido | Não medido | Aguardam sessão autenticada |
| Logout; sessão expirada; isolamento de usuário/escola | Não medido | Não medido | Regressão de integração pendente |

Recebemos indicação de uma conta de **produção** pelo chat. Ela não foi usada. É necessária uma URL de backend de homologação, contas fictícias por canal seguro e orientação de acesso ao iPhone de teste. Recomenda-se trocar a senha exposta no chat. O checkout aponta atualmente para uma API pública de produção em `lib/config/api_config.dart`; a configuração Netlify local está vinculada ao site público. Criar um link de prévia nesse estado **não cria ambiente de homologação isolado**, portanto nenhum deploy de prévia foi feito. As mudanças substanciais no pós-login permanecem fora desta autorização.

## 6. PWA e testes por cenário

| Cenário | Resultado nesta entrega | Limitação |
|---|---|---|
| Primeira abertura e recarga aquecida | 10 pares Chrome e 10 pares WebKit no mesmo servidor local | Simulação Windows, sem PWA instalado |
| Rede móvel limitada | 10 aberturas válidas por artefato, 4 Mb/s/150 ms; um timeout repetido | Emulação Chrome; sem rádio móvel real |
| Login sem autenticar e troca de modo | Campos de usuário e senha aceitaram texto; aba Responsável expôs CPF e PIN no build final | Não valida credenciais nem API |
| Perda e recuperação de rede sem sessão | Em um contexto Chrome, recarga offline falhou; ao voltar online, login tornou-se visível novamente. Sem worker controlador, registros ou CacheStorage nesse contexto | Uma execução, sem dados autenticados nem instalação PWA |
| Atualização do PWA | Testes automatizados de `version.json`, segurança de atualização e lease passaram | Atualização real entre builds no iPhone pendente |
| Fechamento completo, sessão ativa/expirada, logout, troca de seções, perda e recuperação de rede autenticada | Não executados | Dependem de contas de homologação e dispositivo |
| PWA instalado em iPhone / Safari Web Inspector | Não executado | Disponibilidade foi informada, mas o modo de acesso ainda não foi fornecido |
| Emulador Android Studio | AVD `Pixel_7_API_36` e Chrome detectados; abertura automatizada da URL foi bloqueada pela revisão automática de execução | Não é validação iOS nem há resultado visual do emulador |

O build usa `--pwa-strategy=none` e não instalou service worker controlador nos contextos limpos. O worker de migração e caches históricos de um iPhone existente não foram reavaliados nesta entrega. Nenhum cache de informações escolares foi introduzido.

## 7. Design e regressão

Screenshots foram feitos no mesmo viewport mobile **390×844, DPR 3** e desktop **1440×900** com o mesmo manifesto local. Evidências: [mobile antes](performance_evidence/login_before_mobile.png), [mobile depois](performance_evidence/login_after_mobile.png), [desktop antes](performance_evidence/login_before_desktop.png), [desktop depois](performance_evidence/login_after_desktop.png). A diferença média absoluta por canal foi **0,30/255 no mobile** e **0,23/255 no desktop**, máximo de 14/255 e 12/255 respectivamente. Essa diferença decorre principalmente da recompressão; inspeção visual confirma composição, cores, tipografia, posição dos campos e controles equivalentes. A comparação não cobre animação quadro a quadro nem painel autenticado.

`flutter build web --release` concluiu. `flutter analyze` nos seis arquivos Dart alterados não mostrou erros; terminou com 34 avisos/informações preexistentes de import não usado, `withOpacity` e `const` em telas grandes, portanto o exit code foi 1. Passaram **16 testes** de exceção de sessão do responsável, refresh/retry da API e atualização do app (`flutter test` nos cinco arquivos relacionados). Nenhum teste de login real de equipe, aluno ou responsável foi possível. A interação local não autenticada passou para formulário padrão e seleção do modo Responsável.

## 8. Evidências e reprodução

Os JSON brutos estão em [performance_evidence](performance_evidence): `chrome_before/after.json`, `webkit_before/after.json`, `network_before/after.json` e `network_before_retry.json` (contém a 10ª execução substituta). Cada linha registra tempo de campo, FCP, fim do recurso, número de requisições e bytes; Chrome registra *long tasks*. O teste usa um servidor estático local com ETag; a metodologia e os limites de Resource Timing estão descritos na [baseline](ACADEMYHUB_PERFORMANCE_BASELINE.md). `.tmp-audit-build/` foi preservado intacto; `.tmp-audit-after/` registra a iteração intermediária e `.tmp-audit-final/` o artefato medido. São diretórios temporários **não rastreados** e não foram removidos. Há também alterações locais preexistentes em outros arquivos; não foram descartadas.

Para repetir: servir separadamente `.tmp-audit-build/` e `.tmp-audit-final/` na mesma porta e executar 10 contextos novos, cada um seguido de uma recarga, com viewport 390×844/DPR 3. Para rede limitada, aplicar 4 Mb/s/2 Mb/s e 150 ms no Chrome DevTools Protocol. Em uma sessão autenticada futura, usar o mesmo commit/backend, conta fictícia e estado de cache nos dois builds; medir `auth.*`, `session.*`, `dashboard.*` e primeiro frame, além de tempos de API e resposta ao toque no dispositivo.

## 9. Riscos, pendências e recomendação

- O principal custo remanescente é `main.dart.js` de 7,19 MB mais runtime Flutter e fonte Phosphor de 928 KB. Adiar módulos/abas antes do login pode ajudar, mas requer um experimento separado e medições autenticadas para garantir que não transfira a demora para o painel.
- A revalidação de `main.dart.js` deve ser confirmada em uma prévia Netlify isolada e durante atualização de versão, inclusive em iPhone com worker antigo. Caso Netlify ignore o cabeçalho ou sirva ETag incorreto, não há ganho de cache comprovado.
- A meta preliminar de 30% para abertura fria no Chrome não foi atingida. O ganho de 23,5% foi real no ensaio local, mas a condição de rede limitada melhorou apenas 5,7%. A otimização adicional deve focar o bundle e fontes, mantendo autenticação e visual.
- Não há resultado antes/depois para autenticação, painel, navegação, memória, frames, sessão expirada ou PWA instalado em iPhone. Essas lacunas impedem recomendação de liberação.
- A inconsistência de “Começando em breve” para aula de outro dia, documentada na baseline, permanece sem correção porque está fora do escopo autorizado.

**Recomendação:** revisar esta entrega como correção parcial do login. Autorizar teste com backend e contas fictícias de homologação, acesso ao iPhone e uma prévia isolada antes de qualquer mudança substancial no pós-login ou publicação em produção.
