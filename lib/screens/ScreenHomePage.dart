import 'package:academyhub_mobile/model/dashboard_model.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/dashboard_provider.dart';
import 'package:academyhub_mobile/services/performance_trace.dart';
import 'package:academyhub_mobile/widgets/debtors_list_sheet.dart';
// import 'package:academyhub_mobile/dashboard/pending_expenses_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class ScreenHomePage extends StatefulWidget {
  final Function(String filter)? onNavigateToExpenses;
  const ScreenHomePage({super.key, this.onNavigateToExpenses});

  @override
  State<ScreenHomePage> createState() => _ScreenHomePageState();
}

class _ScreenHomePageState extends State<ScreenHomePage> {
  bool _firstReadyFrameMarked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Segurança para evitar erro se sair da tela rápido
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token != null) {
        Provider.of<DashboardProvider>(context, listen: false)
            .fetchDashboard(auth.token!);
      }
    });
  }

  String formatCurrency(double value) {
    if (value.isNaN || value.isInfinite) return "R\$ 0,00";
    return NumberFormat.compactSimpleCurrency(locale: 'pt_BR').format(value);
  }

  // --- AÇÃO: ABRIR LISTA DE DEVEDORES ---
  void _showDebtorsPopup(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite ocupar mais altura
      backgroundColor: Colors.transparent,
      builder: (context) => const DebtorsListSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? const Color(0xFF121212) : theme.scaffoldBackgroundColor;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : theme.cardColor;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F2937);
    final textSecondary = isDark ? Colors.grey[400] : Colors.grey[600];

    return Consumer<DashboardProvider>(
      builder: (context, dashboard, child) {
        final data = dashboard.data;
        final counts = data?.counts;
        final fin = data?.financial;
        final loading = dashboard.isLoading;

        if (loading) return const Center(child: CircularProgressIndicator());
        if (!_firstReadyFrameMarked && data != null) {
          _firstReadyFrameMarked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) PerformanceTrace.mark('dashboard.staff.first_frame');
          });
        }

        // --- CÁLCULOS SEGUROS (PROTEÇÃO CONTRA ERRO DE GRÁFICO) ---
        double receita = (fin?.saldoMes ?? 0).toDouble();
        double despesa = (fin?.despesaMes ?? 0).toDouble();
        double aReceber = (fin?.totalAVencer ?? 0).toDouble();

        // Meta = O que já recebi + O que ainda falta receber
        double totalEsperado = receita + aReceber;

        // Proteção contra divisão por zero (Infinity/NaN causa o quadrado cinza)
        double performanceRecebimento = 0.0;
        if (totalEsperado > 0) {
          performanceRecebimento = (receita / totalEsperado) * 100;
        }

        // Dupla checagem
        if (performanceRecebimento.isNaN || performanceRecebimento.isInfinite) {
          performanceRecebimento = 0.0;
        }

        return Scaffold(
          backgroundColor: backgroundColor,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                await Provider.of<DashboardProvider>(context, listen: false)
                    .fetchDashboard(auth.token!);
              },
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    _buildHeader(textPrimary, textSecondary),
                    SizedBox(height: 24.h),

                    // 1. HERO CARD (PERFORMANCE)
                    Text("Desempenho da Receita",
                        style: _sectionTitleStyle(textPrimary)),
                    SizedBox(height: 12.h),
                    _buildRevenuePerformanceCard(
                        receita,
                        totalEsperado,
                        performanceRecebimento / 100,
                        isDark,
                        cardColor,
                        textPrimary),

                    SizedBox(height: 24.h),

                    // 2. GRID EDUCACIONAL
                    _buildSchoolStatsGrid(
                        counts, isDark, cardColor, textPrimary),

                    SizedBox(height: 24.h),

                    // 3. GRÁFICOS LADO A LADO
                    Text("Balanço & Meta",
                        style: _sectionTitleStyle(textPrimary)),
                    SizedBox(height: 12.h),

                    // [LAYOUT FIX] Definimos altura fixa aqui para garantir que os gráficos renderizem
                    SizedBox(
                      height: 220.h, // Aumentei levemente para dar respiro
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Gráfico Radial
                          Expanded(
                            flex: 5,
                            child: _buildRadialPerformanceCard(
                                performanceRecebimento,
                                isDark,
                                cardColor,
                                textPrimary),
                          ),
                          SizedBox(width: 12.w),
                          // Gráfico de Barras
                          Expanded(
                            flex: 6,
                            child: _buildBarBalanceCard(receita, despesa,
                                isDark, cardColor, textPrimary, textSecondary!),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // 4. MONITOR DE RISCO (CLICÁVEL)
                    Text("Monitor de Risco",
                        style: _sectionTitleStyle(textPrimary)),
                    SizedBox(height: 12.h),
                    _buildDelinquencyCard(
                        fin, isDark, cardColor, textPrimary, textSecondary,
                        onTap: () => _showDebtorsPopup(context)),

                    SizedBox(height: 100.h),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- WIDGETS ---

  Widget _buildHeader(Color primary, Color? secondary) {
    String currentMonth = DateFormat('MMMM', 'pt_BR').format(DateTime.now());
    currentMonth = currentMonth[0].toUpperCase() + currentMonth.substring(1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dashboard",
              style: GoogleFonts.sairaCondensed(
                fontWeight: FontWeight.w700,
                color: primary,
                fontSize: 28.sp,
              ),
            ),
            Text(
              "resumo do mês de $currentMonth",
              style: GoogleFonts.ubuntu(
                fontWeight: FontWeight.w500,
                color: secondary,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
        Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.2))),
          child: Icon(PhosphorIcons.buildings,
              color: Colors.blueAccent, size: 24.sp),
        )
      ],
    );
  }

  Widget _buildRevenuePerformanceCard(double realizado, double esperado,
      double taxa, bool isDark, Color cardColor, Color textColor) {
    // Proteção visual
    if (taxa.isNaN || taxa.isInfinite) taxa = 0;
    if (taxa > 1.0) taxa = 1.0; // Barra cheia no máximo

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5))
          ],
          border: isDark
              ? Border.all(color: Colors.white.withOpacity(0.05))
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Arrecadação Realizada",
                  style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              Text("${(taxa * 100).toInt()}% da Meta",
                  style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF00A859))),
            ],
          ),
          SizedBox(height: 10.h),
          Stack(
            children: [
              Container(
                height: 12.h,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey[200],
                    borderRadius: BorderRadius.circular(6.h)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutExpo,
                height: 12.h,
                width: 300.w * taxa,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00A859), Color(0xFF4ADE80)]),
                    borderRadius: BorderRadius.circular(6.h)),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Em Caixa",
                      style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                  Text(formatCurrency(realizado),
                      style: GoogleFonts.sairaCondensed(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                ],
              ),
              Container(
                  width: 1, height: 30.h, color: Colors.grey.withOpacity(0.2)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("Previsto Total",
                      style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                  Text(formatCurrency(esperado),
                      style: GoogleFonts.sairaCondensed(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSchoolStatsGrid(
      dynamic counts, bool isDark, Color cardColor, Color textColor) {
    return Row(
      children: [
        Expanded(
            child: _buildStatTile(
                "Alunos Ativos",
                counts?.students?.toString() ?? "0",
                PhosphorIcons.student,
                Colors.blueAccent,
                cardColor,
                isDark,
                textColor)),
        SizedBox(width: 12.w),
        Expanded(
            child: _buildStatTile(
                "Turmas",
                counts?.classes?.toString() ?? "0",
                PhosphorIcons.users_three,
                Colors.orangeAccent,
                cardColor,
                isDark,
                textColor)),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, Color accent,
      Color bg, bool isDark, Color textColor) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10)
          ],
          border: Border(left: BorderSide(color: accent, width: 3.w))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 24.sp),
          SizedBox(height: 8.h),
          Text(value,
              style: GoogleFonts.sairaCondensed(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                  color: textColor)),
          Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRadialPerformanceCard(
      double percent, bool isDark, Color cardColor, Color textColor) {
    // Tratamento de valores extremos para evitar crash de renderização
    if (percent.isNaN || percent.isInfinite) percent = 0;
    double displayPercent = percent > 100 ? 100 : percent;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Text("Meta Mensal",
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
          Expanded(
            // [SYNCFUSION] RadialBarSeries pode falhar se não tiver tamanho.
            // O Expanded aqui funciona pois o pai (Row na build) tem altura fixa de 220.h
            child: SfCircularChart(
              margin: EdgeInsets.zero,
              series: <CircularSeries>[
                RadialBarSeries<Map<String, dynamic>, String>(
                  dataSource: [
                    {
                      'x': 'Recebido',
                      'y': displayPercent,
                      'color': const Color(0xFF00A859)
                    },
                    {
                      'x': 'Total',
                      'y': 100.0, // Forçando double
                      'color': isDark ? Colors.black26 : Colors.grey[200]
                    },
                  ],
                  // Tipagem explícita no Mapper para evitar cast errors em Release
                  xValueMapper: (Map<String, dynamic> data, _) =>
                      data['x'] as String,
                  yValueMapper: (Map<String, dynamic> data, _) =>
                      (data['y'] as num).toDouble(),
                  pointColorMapper: (Map<String, dynamic> data, _) =>
                      data['color'] as Color,
                  maximumValue: 100,
                  radius: '100%',
                  innerRadius: '70%',
                  cornerStyle: CornerStyle.bothCurve,
                  trackOpacity: 0.1,
                )
              ],
              annotations: <CircularChartAnnotation>[
                CircularChartAnnotation(
                  widget: Text("${percent.toInt()}%",
                      style: GoogleFonts.sairaCondensed(
                          fontWeight: FontWeight.bold,
                          fontSize: 18.sp,
                          color: textColor)),
                )
              ],
            ),
          ),
          Text("Realizado",
              style: TextStyle(fontSize: 9.sp, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBarBalanceCard(double income, double expense, bool isDark,
      Color cardColor, Color primary, Color secondary) {
    final List<ChartData> chartData = [
      ChartData('Ent', income, Colors.green),
      ChartData('Sai', expense, Colors.redAccent),
    ];

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Balanço Atual",
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              margin: EdgeInsets.symmetric(vertical: 10.h),
              primaryXAxis: CategoryAxis(
                  isVisible: true,
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: const AxisLine(width: 0),
                  labelStyle: TextStyle(fontSize: 10.sp, color: secondary)),
              primaryYAxis: NumericAxis(isVisible: false, minimum: 0),
              series: <CartesianSeries<ChartData, String>>[
                ColumnSeries<ChartData, String>(
                    dataSource: chartData,
                    xValueMapper: (ChartData data, _) => data.x,
                    yValueMapper: (ChartData data, _) => data.y,
                    pointColorMapper: (ChartData data, _) => data.color,
                    borderRadius: BorderRadius.circular(4.r),
                    width: 0.5,
                    dataLabelSettings: DataLabelSettings(
                        isVisible: true,
                        textStyle: TextStyle(fontSize: 9.sp, color: primary),
                        labelAlignment: ChartDataLabelAlignment.outer,
                        builder:
                            (data, point, series, pointIndex, seriesIndex) {
                          // Proteção contra nulos na label
                          final val = point.y;
                          if (val == null) return const SizedBox();

                          return Text(
                            NumberFormat.compact(locale: 'pt_BR').format(val),
                            style: TextStyle(fontSize: 9.sp, color: secondary),
                          );
                        }))
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDelinquencyCard(dynamic fin, bool isDark, Color cardColor,
      Color primary, Color? secondary,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16.r),
          border: Border(left: BorderSide(color: Colors.redAccent, width: 4.w)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10)
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(PhosphorIcons.warning_octagon,
                  color: Colors.red, size: 28.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Inadimplência Atual",
                      style: GoogleFonts.inter(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                  SizedBox(height: 4.h),
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                          text: "${fin?.inadimplenciaAlunos ?? 0} Alunos ",
                          style: TextStyle(
                              color: primary, fontWeight: FontWeight.w600)),
                      TextSpan(
                          text: "(${fin?.inadimplenciaTaxa}%)",
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                    ], style: TextStyle(fontSize: 13.sp)),
                  ),
                  Row(
                    children: [
                      Text("Ver detalhes",
                          style: TextStyle(fontSize: 11.sp, color: secondary)),
                      SizedBox(width: 4.w),
                      Icon(PhosphorIcons.arrow_right,
                          size: 10.sp, color: secondary)
                    ],
                  ),
                ],
              ),
            ),
            // =========================================================================
            // [CORREÇÃO AQUI] Trocado inadimplenciaValor por totalVencido
            // =========================================================================
            Text(formatCurrency((fin?.totalVencido ?? 0).toDouble()),
                style: GoogleFonts.sairaCondensed(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
          ],
        ),
      ),
    );
  }

  TextStyle _sectionTitleStyle(Color color) => GoogleFonts.inter(
      fontSize: 15.sp, fontWeight: FontWeight.w700, color: color);
}

class ChartData {
  final String x;
  final double y;
  final Color color;
  ChartData(this.x, this.y, this.color);
}
