# AcademyHub Mobile — baseline de performance (Etapa 1)

**Data:** 11/10/2026 · **Estado:** auditoria sem correções ou deploy · **Prioridade:** PWA instalado no iPhone.

## 1. Resumo executivo

O login do deploy público demorou **5,20 s de mediana** para apresentar os campos em 10 aberturas sem cache no Chrome mobile emulado; na reabertura, **3,47 s**. Em WebKit simulado no Windows, as medianas foram **4,46 s** e **3,98 s**. Essas são medições do login não autenticado, não equivalem a um PWA instalado no iPhone.

Há três causas demonstradas para o custo de abertura: o login só é liberado depois de `precacheImage` de uma imagem de **682.524 bytes** e de uma espera fixa de **600 ms**; a aplicação distribui um `main.dart.js` único de **7.188.573 bytes** no build local; e o deploy entrega esse bundle com `Cache-Control: no-store`, forçando nova transferência. Na amostra de produção, o bundle transferiu cerca de **1,83 MB** tanto na abertura fria quanto na reabertura.

O código também mostra trabalho antecipado na montagem de abas ocultas após o login. Para o professor, o painel, a preparação de contexto e a aba Turmas iniciam carregamentos próprios; para a gestão, a aba Participantes busca dados de alunos e turmas mesmo oculta. **A quantidade de chamadas efetivamente duplicadas, sua duração e o tempo de “Preparando seu painel…” não puderam ser medidos sem uma conta de teste autenticada.** Não há base para atribuir lentidão a um endpoint ou consulta de banco específico.

**Decisão solicitada para a Etapa 2:** revisar as propostas abaixo e autorizar separadamente a implementação. Nenhum arquivo de aplicação, visual, fluxo ou produção foi alterado nesta etapa.

## 2. Ambiente, versões e método

| Alvo | Versão e condições | O que representa |
|---|---|---|
| Deploy público `https://academyhub-mobile.netlify.app/` | `version.json`: 1.5.8+4, commit `27088b9e788844b0099b9426494f365c292dee02`, publicado em 08/10/2026 20:39:51 UTC | Tempos reais de rede do site público, em navegador automatizado no Windows |
| Checkout local | commit `c195a78ef0875ac77900f41a0585d1603dc0c435`, `pubspec.yaml` 1.5.8+2, com alterações locais preexistentes; Flutter 3.47.0/Dart 3.13.0 | Análise de código e build de auditoria; **não é o mesmo build do deploy** |
| Chrome 155.0.8059.40 | viewport 390×844, DPR 3, toque e modo mobile emulados no Windows | Comparação complementar, não Safari/iPhone |
| Playwright WebKit 26.0 | viewport 390×844, DPR 3, toque e modo mobile emulados no Windows | Simulação WebKit; **não substitui PWA iOS instalado** |

Foram feitas 10 execuções por condição principal. “Frio” = contexto novo sem cache; “aquecido” = recarga no mesmo contexto. A marca de login é o primeiro aparecimento dos campos semânticos `Username/Email` e `Senha`, depois de habilitar a árvore de acessibilidade do Flutter. O valor inclui inicialização, rede, renderização e o custo da instrumentação semântica. `FCP` é apenas um **indicador da primeira pintura do navegador**, possivelmente o splash; não comprova que o formulário já estava visível. `responseEnd` é fim da transferência do recurso, **não mede isoladamente a decodificação ou pintura da imagem**.

Para cada série, mediana = média dos dois valores centrais; P95 = maior valor de 10 execuções (nearest rank); variação = mínimo–máximo. Transferência e contagem incluem apenas recursos da origem do aplicativo vistos pela Resource Timing API. Recursos de outros domínios, WebAssembly de origem externa e tráfego sem `Timing-Allow-Origin` não são integralmente contabilizados. A rede normal não teve latência controlada. Dados de Chrome e WebKit não devem ser subtraídos entre si como se fossem o mesmo aparelho.

**Limitações críticas:** não havia iPhone real/Safari Web Inspector, conta de teste autenticada, acesso ao backend/banco ou logs de produção. As capturas mencionadas no pedido não estavam disponíveis como arquivo no workspace. Os tempos de API, autenticação, painel, navegação entre abas, logout e sessão expirada permanecem pendentes de medição real. Nenhuma credencial foi inventada e nenhuma autenticação de produção foi disparada.

O build de auditoria foi gerado em `.tmp-audit-build/`; a limpeza recursiva dessa pasta foi bloqueada pela revisão automática de execução. Ela permanece como artefato temporário **não rastreado**. As outras alterações locais listadas pelo Git já existiam antes da auditoria e foram preservadas.

## 3. Login — métricas medidas no deploy público

Valores em **milissegundos**, exceto quando indicado. A coluna “variação” é mínimo–máximo.

| Ambiente e cenário | Indicador | Mediana | P95 | Variação |
|---|---|---:|---:|---:|
| Chrome mobile, frio, n=10 | FCP, primeira pintura indicativa | 1.670 | 1.760 | 816–1.760 |
| Chrome mobile, frio, n=10 | Campos do login apresentados | 5.197 | 6.004 | 4.566–6.004 |
| Chrome mobile, frio, n=10 | `main.dart.js` recebido | 2.424 | 2.609 | 1.345–2.609 |
| Chrome mobile, frio, n=10 | Imagem de login recebida | 4.135 | 5.048 | 3.560–5.048 |
| Chrome mobile, aquecido, n=10 | FCP indicativo | 2.392 | 2.852 | 1.804–2.852 |
| Chrome mobile, aquecido, n=10 | Campos do login apresentados | 3.469 | 4.050 | 2.891–4.050 |
| Chrome mobile, aquecido, n=10 | `main.dart.js` recebido | 1.282 | 1.984 | 952–1.984 |
| Chrome mobile, aquecido, n=10 | Imagem de login recebida | 2.726 | 3.187 | 2.132–3.187 |
| WebKit Windows, frio, n=10 | FCP indicativo | 2.948 | 3.711 | 2.099–3.711 |
| WebKit Windows, frio, n=10 | Campos do login apresentados | 4.455 | 5.353 | 3.606–5.353 |
| WebKit Windows, aquecido, n=10 | FCP indicativo | 2.471 | 2.951 | 1.722–2.951 |
| WebKit Windows, aquecido, n=10 | Campos do login apresentados | 3.980 | 4.644 | 3.152–4.644 |

| Ambiente e cenário | Requisições da origem, mediana | Transferência da origem, mediana | Tarefas longas, mediana | Soma da duração de tarefas longas, mediana |
|---|---:|---:|---:|---:|
| Chrome frio | 13 | 3.566.047 B | 4 | 661 ms |
| Chrome aquecido | 13 | 2.876.362 B | 2 | 148 ms |
| WebKit frio | 13 | 2.951.935 B | indisponível¹ | indisponível¹ |
| WebKit aquecido | 13 | 2.951.881 B | indisponível¹ | indisponível¹ |

¹ A API `PerformanceObserver` para `longtask` não forneceu entradas no WebKit testado. Isso **não significa zero trabalho longo**.

Em uma execução adicional no Chrome, o heap JavaScript após o login estar disponível foi **43.757.924 B**. É uma amostra isolada, não uma distribuição ou medida da memória total do processo: exclui memória nativa, CanvasKit/WebAssembly e GPU. Não permite concluir se há vazamento. O observador de LCP não produziu entradas para o conteúdo Flutter; CLS retornou zero, mas não cobre a composição no canvas; INP autenticado e perda de frames não foram medidos. Para esse app, a marca do formulário e um perfil de frames no dispositivo são alternativas mais verificáveis.

O Chrome registrou, na primeira execução fria, **1.829.785 B** transferidos para `main.dart.js`, **928.448 B** para `Phosphor.ttf` e **682.824 B** para `imagem_de_login.jpg`, incluindo overhead de Resource Timing. Não houve chamada de API de dados ou autenticação antes do login nas amostras; a consulta de atualização foi `version.json`. O build local inclui imagens maiores (`DasboardLogin.svg` 4.589.058 B e `LoginDash.jpg` 4.052.439 B), porém **elas não apareceram nas requisições iniciais observadas** e não devem ser culpadas pelo download inicial sem evidência adicional.

Uma conferência complementar em Chrome desktop (1365×768, **uma** execução no deploy) encontrou os campos em **5.245 ms** e FCP em **1.848 ms**. Uma única execução não fornece mediana nem P95 confiáveis e serve apenas como comparação de funcionamento, não como referência de performance desktop.

O build local de auditoria (Flutter 3.47.0, servidor HTTP local sem compressão) apresentou campos em **2.939 ms** de mediana a frio e **1.267 ms** em recarga, 10 execuções cada; P95 **3.981 ms** e **1.682 ms**. Estes números servem para repetir testes do checkout atual; **não são comparação antes/depois com produção**. Seu `main.dart.js` gerado tem 7.188.573 B e não há chunks Dart de carregamento adiado identificados.

## 4. Pós-login — sequência e duração

| Etapa | Código/endpoints identificados | Duração medida |
|---|---|---|
| Toque em Entrar e diálogo “Validando acesso...” | `lib/screens/loginPage.dart` `_handleStandardLogin`, `_showLoadingDialog` | Pendente de sessão de teste |
| Autenticação | `AuthProvider.login`; equipe `POST /api/auth/login`, aluno `POST /api/auth/student/login`; identificador sem `@` tenta aluno antes de usuário da equipe | Pendente |
| Persistência e sessão | `AuthSessionManager.saveLogin`, `SharedPreferences`, armazenamento do refresh token | Pendente |
| Escola/permissões/contexto | `SchoolProvider.loadSchoolData`, `TeacherClassContextHelper.ensureDataLoaded`; `GET /api/schools/:id`, `/api/school-years`, `/api/terms`, `/api/classes`, `/api/horarios` conforme papel | Pendente |
| “Preparando seu painel...” | `TeacherDashboardView._fetchDashboardData` espera termos e depois horários; para gestão, `ScreenHomePage` consulta dashboard | Pendente |
| Primeiro painel visível e interativo | `TeacherDashboardView` só troca `_isLoading` após agenda processada; animação de entrada de 900 ms; outras abas já podem ser montadas | Pendente |

No painel do professor, a consulta de termos precede a de horários no caminho sem cache (`screen_teacher_dashboard.dart:149–208`). A obtenção da escola após login é disparada sem `await` (`auth_provider.dart:253–267`). O helper de contexto também busca anos, períodos, turmas e horários em sequência (`teacher_class_context_helper.dart:47–113`). Essas são relações **comprovadas no código**, não duração medida nem prova de que o backend seja lento.

## 5. Navegação e inicialização antecipada

| Fluxo | Evidência de código | Resultado de tempo/frames |
|---|---|---|
| Professor: Início, Alunos, Turmas, Mais e retorno | `ProfessorMainScreen` usa `IndexedStack` (`professor_main_screen.dart:220–269`), mantendo estado das abas depois da montagem | Não medido sem login |
| Professor: entrada no painel | `ProfessorMainScreen.initState` chama `_primeTeacherEffectiveContext(forceRefresh: true)`; `TeacherDashboardView.initState` chama `_fetchDashboardData`; `TeacherActivityClassSelectionScreen.initState` chama `_ensureDataLoaded` | **Risco estrutural** de requisições simultâneas e redundantes; multiplicidade real não medida |
| Gestão: entrada no painel | `StaffDashboardView` monta `ScreenparticipantesMobile` em `IndexedStack`; `ScreenParticipantes.initState` consulta alunos, matrículas, turmas e solicitações | Carregamento antecipado demonstrado no código; duração não medida |
| Logout e retorno ao login | `AuthProvider.logout` aguarda logout remoto (até 5 s no serviço), limpa providers e armazenamento, depois notifica/navega | Duração e responsividade não medidas |
| Reabertura com sessão ativa | `AuthWrapper` usa `tryAutoLogin`; equipe com refresh token pode aguardar `POST /api/auth/refresh` (timeout de 15 s) antes de exibir painel | Duração não medida |

Os providers de turmas e horários não compartilham uma operação em andamento (`class_provider.dart:44–60`, `horario_provider.dart:55–79`). Como os caminhos acima podem iniciar no mesmo frame, há **possibilidade de chamadas repetidas**, a confirmar em rastreio autenticado. O `IndexedStack` preserva dados e estado ao alternar abas, mas sua montagem inicial pode antecipar trabalho de abas não selecionadas.

## 6. PWA, cache e cenários

O `manifest.json` usa `display: standalone`, `start_url: .` e ícones de instalação. O build de produção é feito com `--pwa-strategy=none`; `web/flutter_service_worker.js` é um worker de migração sem interceptação de `fetch` nem `CacheStorage`, que se desregistra ao ativar. Nos contextos limpos de Chrome e WebKit, `navigator.serviceWorker.controller` era falso. Um iPhone que já carregou versões antigas pode ter estado diferente: **a migração de worker histórico não foi validada**.

| Cenário solicitado | Evidência obtida nesta etapa | Limite |
|---|---|---|
| Primeira abertura sem cache | 10 execuções Chrome e 10 WebKit no deploy | Simulação Windows, sem instalação iOS |
| Reabertura com cache aquecido | 10 execuções Chrome e 10 WebKit no mesmo contexto | Recarga de página, não retomada após encerramento do PWA iOS |
| Fechamento completo | Novo contexto simula armazenamento limpo | Não representa suspensão/encerramento pelo iOS |
| Sessão ativa, login após logout, sessão expirada | Não executados | Requer contas de teste e sessão real |
| Troca entre Início, Alunos, Turmas e Mais | Não executada | Requer conta com papel apropriado |
| Rede normal | Medida no deploy sem limitação artificial | Estabilidade e tipo de conexão física não controlados |
| Rede móvel limitada | 10 aberturas frias no Chrome com 4 Mb/s de download, 2 Mb/s de upload e 150 ms de latência | Emulação de rede no Chrome, não rádio móvel real |
| Rede lenta/instável; perda e recuperação | Após login disponível, recarga totalmente offline falhou com `ERR_INTERNET_DISCONNECTED`; retorno online permitiu abrir login novamente | Uma execução; não mede preservação de dados autenticados |
| Atualização do PWA | Código/cabeçalhos inspecionados; em fixture local com `buildId` remoto diferente apareceu a ação “Atualizar agora” | Botão não acionado; troca real de build em iPhone não executada |
| Inicialização com dados em cache | Cache HTTP de recursos estáticos observado | Cache de dados escolares autenticados não testado |

O deploy respondeu `Cache-Control: no-store, must-revalidate, no-cache` para `main.dart.js` e documento; a imagem usa `no-cache, must-revalidate`. Isso é consistente com a transferência repetida do bundle nas amostras aquecidas e com a ausência de cache offline controlado por service worker. O aplicativo evita a estratégia antiga que poderia mostrar dados escolares desatualizados, mas qualquer proposta de cache na Etapa 2 precisará separar recursos estáticos versionados de dados privados, validar usuário/escola e indicar claramente a idade de dados offline.

**Rede móvel simulada, deploy público, Chrome, 10 aberturas frias:**

| Indicador | Mediana | P95 | Variação |
|---|---:|---:|---:|
| Campos do login apresentados | 17.266 ms | 17.381 ms | 16.569–17.381 ms |
| FCP indicativo | 3.660 ms | 3.720 ms | 2.764–3.720 ms |
| `main.dart.js` recebido | 10.846 ms | 10.886 ms | 10.041–10.886 ms |
| Imagem de login recebida | 16.443 ms | 16.547 ms | 15.688–16.547 ms |

O ensaio de falha de rede usou um contexto Chrome aquecido. No mesmo contexto limpo, `navigator.serviceWorker.getRegistrations()` e `caches.keys()` retornaram listas vazias, o campo pôde receber texto, a recarga offline falhou e uma nova navegação após religar a rede apresentou o login. Isso verifica apenas o retorno de uma sessão **sem autenticação**. Na simulação de atualização foi alterado somente o `version.json` de um build temporário local; o arquivo foi restaurado em seguida. Não houve atualização de produção nem migração de worker legado nesse ensaio.

## 7. Gargalos e hipóteses, por impacto

| Impacto | Estado | Evidência | Proposta para avaliação na Etapa 2 |
|---|---|---|---|
| Alto | **Comprovado no código e no deploy** | `loginPage.dart:68–84, 380–409`: imagem pré-decodificada antes do formulário e espera fixa de 600 ms; imagem termina de chegar na mediana de 4,135 s e campos surgem aos 5,197 s a frio no Chrome | Permitir formulário utilizável assim que seus elementos essenciais estiverem prontos, preservando imagem e transição; medir comparação visual antes/depois. Otimizar bytes da imagem sem perda perceptível |
| Alto | **Comprovado no build/cabeçalhos** | Bundle Dart único de 7,19 MB local; produção transfere ~1,83 MB novamente; `netlify.toml` marca `main.dart.js` como `no-store` | Investigar divisão de código por rotas/módulos e cache seguro de arquivos estáticos versionados, com invalidação de build; não armazenar dados escolares como atuais |
| Alto | **Comprovado no código; custo real não medido** | `IndexedStack` monta abas ocultas e inicia buscas de Turmas/Participantes; ausência de deduplicação de chamadas em andamento | Carregar dados da aba quando aberta, preservar dados válidos por usuário/escola/ano e deduplicar operações concorrentes |
| Médio/alto | **Comprovado no código; duração não medida** | `_fetchDashboardData` aguarda termos → horários antes de trocar `_isLoading`; helper prepara anos → termos → turmas → horários | Instrumentar cada etapa e paralelizar somente consultas independentes; distinguir dados indispensáveis dos secundários, mantendo erros visíveis |
| Médio | **Comprovado no build e rede** | `Phosphor.ttf` 928.148 B no build, ~928 KB de transferência no Chrome frio; fontes externas adicionais observadas | Verificar subconjunto de glifos realmente usados e carregamento de fontes, com comparação visual de ícones/tipografia |
| Indeterminado | **Hipótese** | Requisições duplicadas, API lenta, consultas de banco, falhas com retry e excesso de memória/frames após login não puderam ser observados | Rastrear sessão autenticada com marcação de etapas, `Server-Timing`/logs e perfil de frames em iPhone |

Nenhuma medição de API ou banco foi apresentada como causa comprovada. A contagem de requisições iniciais inclui apenas o estado sem login. Não houve alteração de design nem de animação nesta auditoria.

## 8. Verificação separada da lógica de “próxima aula”

Há uma inconsistência **reproduzível pela lógica do código**: quando não há aula hoje, `_findNextDayWithClasses` seleciona a primeira aula do próximo dia encontrado e define o título “Próximas Aulas • Quinta”, por exemplo (`screen_teacher_dashboard.dart:298–314`). O chip dessa aula chama `_minutesUntil(classInfo.startTime)`, que subtrai apenas a **hora de hoje** da hora da aula e limita o resultado a zero (`:381–385`); zero vira “Começando em breve” (`:1003–1008`). Assim, se for domingo às 19h32 e a próxima aula selecionada for quinta às 07h30, o chip exibirá “Começando em breve”, embora faltarem dias. O uso de `DateTime.now()` segue o fuso do dispositivo; não há data da próxima ocorrência nesse cálculo.

Isso confirma um defeito na **mensagem de contagem regressiva para aulas de outro dia**. Sem a grade real, período letivo e fuso do aparelho da captura, não é possível confirmar se quinta-feira era a próxima data correta nem se os dados estavam atualizados. Esta verificação não altera a conclusão de performance.

## 9. Riscos e dependências para corrigir

- **Visual:** qualquer compressão de imagem/fonte e mudança de momento de carregamento exige screenshots pareados em 390×844 e desktop, incluindo transições, para comprovar equivalência visual.
- **Segurança e consistência:** cache de turmas/alunos precisa de escopo por usuário, escola, ano e validade; logout e troca de conta precisam invalidar dados privados. Dados offline devem ser marcados como tal.
- **Autenticação:** não reduzir tempo pulando refresh, validação de permissões ou limpeza de sessão. A transição do login ao painel deve manter erros recuperáveis visíveis.
- **PWA:** alterações de cache precisam ser testadas com worker legado, atualização entre versões e recuperação de rede em iPhone real.
- **Dependências de medição:** contas de teste de equipe, aluno e responsável; dispositivo iOS com Safari Web Inspector; logs/traces da API e acesso a métricas de banco. O commit do deploy deve ser alinhado ao commit sob correção antes de comparar resultados.

## 10. Plano de repetição após correção

1. Congelar um único commit e build identificável; registrar versão, iPhone/iOS, navegador, rede, escola de teste, papel e estado do cache.
2. Em iPhone com PWA instalado, executar **pelo menos 10 vezes** cada cenário principal: abertura fria, aquecida, após encerramento, sessão ativa, login após logout, rede Wi-Fi e móvel, sessão expirada e atualização. Repetir em Safari; usar WebKit Windows e Chrome mobile apenas como complementos.
3. Marcar tempos no cliente para `tap`, início/fim de `/auth/login` ou equivalente, persistência, refresh, escola/permissões, anos/períodos, turmas/horários, primeiro painel visível e primeiro toque atendido. Correlacionar com logs de API e banco sem gravar credenciais/dados sensíveis.
4. Registrar HAR, transferências, requisições repetidas, long tasks/frames e memória via Safari Web Inspector; para CanvasKit, usar marcas de primeiro frame e interação, pois LCP/CLS/INP do DOM podem não representar o conteúdo Flutter.
5. Repetir navegação Início ↔ Alunos/Turmas/Mais, retorno, logout e recuperação após perda de rede. Comparar mediana, P95 e mínimo–máximo, com séries por papel e cenário.
6. Fazer screenshots automatizados antes/depois no mesmo viewport e revisar imagem, cores, tipografia, espaçamentos, animações e barra inferior. Executar build, testes regressivos de autenticação e testes de isolamento de escola/usuário antes de qualquer recomendação de liberação.

**Conclusão da Etapa 1:** a abertura do login tem gargalos locais e de distribuição com evidência mensurável. O pós-login e a navegação têm riscos estruturais claros, mas seus tempos e impacto de API permanecem não medidos. A Etapa 2 deve começar somente após autorização explícita.
