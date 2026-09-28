import 'package:academyhub_mobile/model/guardian_auth_model.dart';
import 'package:academyhub_mobile/screens/guardian_pin_recovery_sheet.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';

enum _LoginMode { standard, guardian }

class Loginpage extends StatefulWidget {
  final bool startInGuardianMode;

  const Loginpage({
    super.key,
    this.startInGuardianMode = false,
  });

  @override
  State<Loginpage> createState() => _LoginpageState();
}

class _LoginpageState extends State<Loginpage> {
  final _standardFormKey = GlobalKey<FormState>();
  final _guardianFormKey = GlobalKey<FormState>();

  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _guardianCpfController = TextEditingController();
  final _guardianPinController = TextEditingController();

  final _guardianCpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {'#': RegExp(r'\d')},
  );

  bool _rememberMe = false;
  bool _isPasswordVisible = false;
  bool _isGuardianPinVisible = false;
  bool _isLoading = false;
  bool _isScreenReady = false;
  _LoginMode _loginMode = _LoginMode.standard;

  @override
  void initState() {
    super.initState();
    _loginMode =
        widget.startInGuardianMode ? _LoginMode.guardian : _LoginMode.standard;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isScreenReady) {
      _preloadAssets();
    }
  }

  Future<void> _preloadAssets() async {
    try {
      await precacheImage(
        const AssetImage('lib/assets/imagem_de_login.jpg'),
        context,
      );
      await Future.delayed(const Duration(milliseconds: 600));
    } catch (e) {
      debugPrint('Erro ao carregar imagem de login: $e');
    }

    if (mounted) {
      setState(() {
        _isScreenReady = true;
      });
    }
  }

  Future<void> _showLoadingDialog(String label) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 24.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFFDDA0DD),
                strokeWidth: 3,
              ),
              SizedBox(height: 16.h),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissDialogIfNeeded() {
    if (!mounted) return;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _showStatusDialog({
    required String title,
    required String message,
    bool isError = false,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22.r),
        ),
        titlePadding: EdgeInsets.fromLTRB(24.w, 22.h, 24.w, 8.h),
        contentPadding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
        actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        title: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color:
                    isError ? const Color(0xFFFFEFEF) : const Color(0xFFF4E7F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color:
                    isError ? const Color(0xFFC62828) : const Color(0xFF7C4D7E),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 24.sp,
                  fontFamily: 'GR Milesons Three',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: const Color(0xFF5E6370),
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Text(
                'Fechar',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStandardLogin() async {
    if (!(_standardFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);
    await _showLoadingDialog('Validando acesso...');

    try {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();

      await authProvider.login(
        _identifierController.text.trim(),
        _passwordController.text,
        context,
      );

      if (!mounted) return;
      _dismissDialogIfNeeded();
    } catch (error) {
      if (!mounted) return;
      _dismissDialogIfNeeded();
      await _showStatusDialog(
        title: 'Não foi possível entrar',
        message: error.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<GuardianSchoolOption?> _showGuardianSchoolSelector({
    required String title,
    required String message,
    required List<GuardianSchoolOption> candidateSchools,
  }) {
    return showModalBottomSheet<GuardianSchoolOption>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (modalContext) => _GuardianSchoolSelectorSheet(
        title: title,
        message: message,
        candidateSchools: candidateSchools,
      ),
    );
  }

  Future<void> _handleGuardianLogin({String? schoolPublicId}) async {
    if (!(_guardianFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final cpf = _guardianCpfFormatter.getUnmaskedText();
    final pin = _guardianPinController.text.trim();

    setState(() => _isLoading = true);
    await _showLoadingDialog('Entrando como responsável...');

    try {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();

      final result = await authProvider.loginGuardian(
        schoolPublicId: schoolPublicId,
        cpf: cpf,
        pin: pin,
      );

      if (!mounted) return;
      _dismissDialogIfNeeded();

      if (result.requiresSchoolSelection) {
        final selectedSchool = await _showGuardianSchoolSelector(
          title: 'Selecione a escola',
          message: result.message,
          candidateSchools: result.candidateSchools,
        );

        if (selectedSchool == null || !mounted) {
          return;
        }

        await _handleGuardianLogin(
          schoolPublicId: selectedSchool.schoolPublicId,
        );
        return;
      }

      if (!result.isAuthenticated) {
        await _showStatusDialog(
          title: 'Acesso não liberado',
          message: result.message,
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _dismissDialogIfNeeded();
      await _showStatusDialog(
        title: 'Acesso não liberado',
        message: error.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openGuardianFirstAccess() async {
    final result = await showModalBottomSheet<_GuardianFirstAccessOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => const GuardianFirstAccessSheet(),
    );

    if (!mounted || result == null) return;

    _guardianCpfFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: result.cpfDigits),
    );
    _guardianCpfController.text = _guardianCpfFormatter.getMaskedText();
    setState(() {
      _loginMode = _LoginMode.guardian;
      _guardianPinController.clear();
    });
  }

  Future<void> _openGuardianPinRecovery() async {
    final result = await showModalBottomSheet<GuardianPinRecoveryOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: !_isLoading,
      enableDrag: !_isLoading,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => const GuardianPinRecoverySheet(),
    );

    if (!mounted || result == null) return;

    _guardianCpfFormatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(text: result.cpfDigits),
    );
    _guardianCpfController.text = _guardianCpfFormatter.getMaskedText();
    setState(() {
      _loginMode = _LoginMode.guardian;
      _guardianPinController.clear();
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _guardianCpfController.dispose();
    _guardianPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFDDA0DD);

    if (!_isScreenReady) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'lib/assets/logo_chapeu_academy.svg',
                width: 70.w,
                height: 70.h,
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: 150.w,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey[200],
                  color: themeColor,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            Container(
              height: 350.h,
              width: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('lib/assets/imagem_de_login.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, -40.h),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40.r),
                    topRight: Radius.circular(40.r),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 30.h),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 520.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'lib/assets/logo_chapeu_academy.svg',
                          width: 40.w,
                          height: 40.h,
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          _loginMode == _LoginMode.standard
                              ? 'Bem-vindo!'
                              : 'Acesso do responsável',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF1E1E1E),
                            fontSize: _loginMode == _LoginMode.standard
                                ? 22.sp
                                : 20.sp,
                            fontFamily: 'GR Milesons Three',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        SizedBox(
                          width: 290.w,
                          child: Text(
                            _loginMode == _LoginMode.standard
                                ? 'Acesse sua conta e continue sua jornada educacional.'
                                : 'Entre com seu CPF e PIN de 6 dígitos.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: const Color(0xFFA6A8A9),
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                        SizedBox(height: 28.h),
                        _LoginModeSwitch(
                          currentMode: _loginMode,
                          onChanged: (mode) {
                            if (_isLoading) return;
                            setState(() => _loginMode = mode);
                          },
                        ),
                        SizedBox(height: 24.h),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _loginMode == _LoginMode.standard
                              ? _buildStandardLogin(themeColor)
                              : _buildGuardianLogin(themeColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardLogin(Color themeColor) {
    return Form(
      key: _standardFormKey,
      child: Column(
        key: const ValueKey('standard_login'),
        children: [
          CustomTextFormField(
            controller: _identifierController,
            hintText: 'Username/Email',
            icon: PhosphorIcons.envelope_fill,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Por favor, insira seu e-mail, usuário ou matrícula.';
              }
              return null;
            },
          ),
          SizedBox(height: 16.h),
          CustomTextFormField(
            controller: _passwordController,
            hintText: 'Senha',
            icon: PhosphorIcons.lock_key_fill,
            isPassword: true,
            obscureText: !_isPasswordVisible,
            onToggleVisibility: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor, insira sua senha.';
              }
              return null;
            },
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              SizedBox(
                height: 24.h,
                width: 24.w,
                child: Checkbox(
                  value: _rememberMe,
                  activeColor: themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  side: const BorderSide(
                    color: Color(0xFFAFAFAF),
                    width: 1.5,
                  ),
                  onChanged: _isLoading
                      ? null
                      : (val) => setState(() => _rememberMe = val!),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                'Lembrar-me',
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFA6A8A9),
                ),
              ),
            ],
          ),
          SizedBox(height: 32.h),
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleStandardLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.2),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 22.h,
                      width: 22.h,
                      child: CircularProgressIndicator(
                        color: themeColor,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Entrar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23.sp,
                        fontFamily: 'GR Milesons Three',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 36.h),
          InkWell(
            onTap: _isLoading ? null : () {},
            borderRadius: BorderRadius.circular(10.r),
            child: Container(
              width: 44.w,
              height: 44.h,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7.r),
                ),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: SvgPicture.asset(
                  'lib/assets/google-icon-logo-svgrepo-com.svg',
                  width: 24.w,
                  height: 24.h,
                ),
              ),
            ),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildGuardianLogin(Color themeColor) {
    return Form(
      key: _guardianFormKey,
      child: Column(
        key: const ValueKey('guardian_login'),
        children: [
          CustomTextFormField(
            controller: _guardianCpfController,
            hintText: 'CPF do responsável',
            icon: Icons.badge_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [_guardianCpfFormatter],
            validator: (value) {
              if (_guardianCpfFormatter.getUnmaskedText().length != 11) {
                return 'Informe um CPF válido.';
              }
              return null;
            },
          ),
          SizedBox(height: 16.h),
          CustomTextFormField(
            controller: _guardianPinController,
            hintText: 'PIN de 6 dígitos',
            icon: Icons.pin_outlined,
            isPassword: true,
            obscureText: !_isGuardianPinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onToggleVisibility: () {
              setState(() {
                _isGuardianPinVisible = !_isGuardianPinVisible;
              });
            },
            validator: (value) {
              final credential = (value ?? '').trim();
              if (!RegExp(r'^\d{6}$').hasMatch(credential)) {
                return 'O PIN deve ter 6 dígitos.';
              }
              return null;
            },
          ),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleGuardianLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.18),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 22.h,
                      width: 22.h,
                      child: CircularProgressIndicator(
                        color: themeColor,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Entrar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23.sp,
                        fontFamily: 'GR Milesons Three',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 14.h),
          TextButton.icon(
            onPressed: _isLoading ? null : _openGuardianPinRecovery,
            icon:
                const Icon(Icons.lock_reset_rounded, color: Color(0xFF7C4D7E)),
            label: Text(
              'Esqueci meu PIN',
              style: GoogleFonts.inter(
                color: const Color(0xFF7C4D7E),
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 2.h),
            child: Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFE1DCE3))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  child: Text(
                    'ou',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF8B8D96),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Color(0xFFE1DCE3))),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _isLoading ? null : _openGuardianFirstAccess,
            icon: const Icon(Icons.key_outlined, color: Color(0xFF7C4D7E)),
            label: Text(
              'Primeiro acesso',
              style: GoogleFonts.inter(
                color: const Color(0xFF7C4D7E),
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GuardianFirstAccessSheet extends StatefulWidget {
  const GuardianFirstAccessSheet({
    super.key,
  });

  @override
  State<GuardianFirstAccessSheet> createState() =>
      _GuardianFirstAccessSheetState();
}

class _GuardianFirstAccessSheetState extends State<GuardianFirstAccessSheet> {
  final _studentNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _cpfController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  final _schoolStudentFormKey = GlobalKey<FormState>();
  final _cpfFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();

  final _cpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {'#': RegExp(r'\d')},
  );

  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  bool _isPinVisible = false;
  bool _isConfirmPinVisible = false;
  String? _errorMessage;
  String? _challengeId;
  String? _verificationToken;
  GuardianFirstAccessStartResult? _startResult;
  GuardianCandidate? _selectedGuardian;
  GuardianVerificationResult? _verificationResult;
  GuardianPinSetupResult? _pinResult;
  GuardianSchoolOption? _selectedSchoolOption;
  String _lastLookupFingerprint = '';
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  String get _birthDateApiValue {
    if (_selectedBirthDate == null) return '';
    return DateFormat('yyyy-MM-dd').format(_selectedBirthDate!);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(now.year - 12),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      locale: const Locale('pt', 'BR'),
    );

    if (pickedDate == null) return;

    setState(() {
      _selectedBirthDate = pickedDate;
      _birthDateController.text = DateFormat('dd/MM/yyyy').format(pickedDate);
    });
  }

  void _setError(String? message) {
    setState(() {
      _errorMessage = message;
    });
  }

  Future<void> _startFirstAccess() async {
    if (!(_schoolStudentFormKey.currentState?.validate() ?? false)) return;
    if (_selectedBirthDate == null) {
      _setError('Selecione a data de nascimento do aluno.');
      return;
    }

    final lookupFingerprint =
        '${_studentNameController.text.trim().toLowerCase()}|$_birthDateApiValue';
    final waitingSchoolSelection =
        (_startResult?.candidateSchools.isNotEmpty ?? false) &&
            lookupFingerprint == _lastLookupFingerprint;

    if (waitingSchoolSelection && _selectedSchoolOption == null) {
      _setError('Selecione a escola correspondente para continuar.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result =
          await context.read<AuthProvider>().startGuardianFirstAccess(
                schoolPublicId: waitingSchoolSelection
                    ? _selectedSchoolOption?.schoolPublicId
                    : null,
                studentFullName: _studentNameController.text.trim(),
                birthDate: _birthDateApiValue,
              );

      if (result.requiresSchoolSelection) {
        setState(() {
          _startResult = result;
          _selectedSchoolOption = null;
          _lastLookupFingerprint = lookupFingerprint;
        });
        return;
      }

      if (!result.isChallengeStarted) {
        _setError(
          result.message.isNotEmpty
              ? result.message
              : 'Não foi possível validar os dados informados.',
        );
        return;
      }

      setState(() {
        _challengeId = result.challengeId;
        _startResult = result;
        _selectedGuardian = null;
        _verificationResult = null;
        _verificationToken = null;
        _pinResult = null;
        _pinController.clear();
        _confirmPinController.clear();
        _selectedSchoolOption = null;
        _lastLookupFingerprint = lookupFingerprint;
        _stepIndex = 1;
      });
    } catch (error) {
      _setError(error.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyGuardian() async {
    if (_selectedGuardian == null) {
      _setError('Escolha o vínculo correspondente antes de continuar.');
      return;
    }

    if (!(_cpfFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result =
          await context.read<AuthProvider>().verifyGuardianResponsible(
                challengeId: _challengeId!,
                optionId: _selectedGuardian!.optionId,
                cpf: _cpfFormatter.getUnmaskedText(),
              );

      setState(() {
        _verificationResult = result;
        _verificationToken = result.verificationToken;
        _pinController.clear();
        _confirmPinController.clear();

        if (result.isAlreadyLinked) {
          _pinResult = GuardianPinSetupResult(
            status: result.status,
            identifierType: result.identifierType ?? 'cpf',
            identifierMasked:
                result.identifierMasked ?? _cpfFormatter.getMaskedText(),
            message: result.message,
          );
          _stepIndex = 4;
        } else if (result.requiresPinStep) {
          _stepIndex = 3;
        } else {
          _errorMessage = result.message;
        }
      });
    } catch (error) {
      _setError(error.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitGuardianPinStep() async {
    if (!(_pinFormKey.currentState?.validate() ?? false)) return;

    final pin = _pinController.text.trim();
    final requiresExistingPin =
        _verificationResult?.requiresExistingPin ?? false;
    final confirmPin = _confirmPinController.text.trim();

    if (!requiresExistingPin && pin != confirmPin) {
      _setError('Os PINs informados precisam ser iguais.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = requiresExistingPin
          ? await auth.linkGuardianStudentWithExistingPin(
              challengeId: _challengeId!,
              verificationToken: _verificationToken!,
              pin: pin,
            )
          : await auth.setGuardianPin(
              challengeId: _challengeId!,
              verificationToken: _verificationToken!,
              pin: pin,
            );

      setState(() {
        _pinResult = result;
        _stepIndex = 4;
      });
    } catch (error) {
      _setError(error.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _studentNameController.dispose();
    _birthDateController.dispose();
    _cpfController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, bottomInset + 20.h),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560.w),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 56.w,
                        height: 5.h,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD2D7DF),
                          borderRadius: BorderRadius.circular(99.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Primeiro acesso',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF8B8D96),
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Text(
                                'Crie seu acesso',
                                style: TextStyle(
                                  color: const Color(0xFF1E1E1E),
                                  fontSize: 21.sp,
                                  fontFamily: 'GR Milesons Three',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                'Confirme o vínculo com o aluno e finalize seu acesso.',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF6F7480),
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8.w),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tightFor(
                            width: 36.w,
                            height: 36.h,
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    _GuardianStepHeader(currentStep: _stepIndex),
                    if (_errorMessage != null) ...[
                      SizedBox(height: 16.h),
                      _InlineFeedback(message: _errorMessage!, isError: true),
                    ],
                    SizedBox(height: 18.h),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildCurrentStep(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_stepIndex) {
      case 0:
        return _buildStudentStep();
      case 1:
        return _buildSelectGuardianStep();
      case 2:
      case 3:
        return _buildCpfOrPinStep();
      case 4:
        return _buildSuccessStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStudentStep() {
    final List<GuardianSchoolOption> candidateSchools =
        _startResult?.candidateSchools ?? const <GuardianSchoolOption>[];
    final lookupFingerprint =
        '${_studentNameController.text.trim().toLowerCase()}|$_birthDateApiValue';
    final showSchoolChoices = candidateSchools.isNotEmpty &&
        lookupFingerprint == _lastLookupFingerprint;

    return Form(
      key: _schoolStudentFormKey,
      child: Column(
        key: const ValueKey('guardian_step_student'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTextFormField(
            controller: _studentNameController,
            hintText: 'Nome completo do aluno',
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Informe o nome completo do aluno.';
              }
              return null;
            },
          ),
          SizedBox(height: 16.h),
          CustomTextFormField(
            controller: _birthDateController,
            hintText: 'Data de nascimento',
            icon: Icons.calendar_month_outlined,
            readOnly: true,
            onTap: _pickBirthDate,
            validator: (_) {
              if (_selectedBirthDate == null) {
                return 'Selecione a data de nascimento.';
              }
              return null;
            },
          ),
          if (showSchoolChoices) ...[
            SizedBox(height: 16.h),
            _InlineFeedback(
              message: _startResult?.message ??
                  'Encontramos mais de uma escola com um aluno compatível.',
              isError: false,
            ),
            SizedBox(height: 14.h),
            Text(
              'Selecione a escola para continuar:',
              style: GoogleFonts.inter(
                color: const Color(0xFF1E1E1E),
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 12.h),
            ...candidateSchools.map(
              (school) => Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: _GuardianSchoolChoiceTile(
                  school: school,
                  isSelected: _selectedSchoolOption?.schoolPublicId ==
                      school.schoolPublicId,
                  onTap: () {
                    setState(() {
                      _selectedSchoolOption = school;
                      _errorMessage = null;
                    });
                  },
                ),
              ),
            ),
          ],
          SizedBox(height: 24.h),
          _PrimaryActionButton(
            label: showSchoolChoices ? 'Continuar' : 'Buscar responsáveis',
            isLoading: _isLoading,
            onPressed: _startFirstAccess,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectGuardianStep() {
    final guardians = _startResult?.guardians ?? const <GuardianCandidate>[];

    return Column(
      key: const ValueKey('guardian_step_select'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecione o vínculo correspondente:',
          style: GoogleFonts.inter(
            color: const Color(0xFF1E1E1E),
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 12.h),
        ...guardians.map(
          (guardian) => Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: _GuardianChoiceTile(
              guardian: guardian,
              isSelected: _selectedGuardian?.optionId == guardian.optionId,
              onTap: () {
                setState(() {
                  _selectedGuardian = guardian;
                  _stepIndex = 2;
                  _errorMessage = null;
                });
              },
            ),
          ),
        ),
        SizedBox(height: 10.h),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _stepIndex = 0;
                    _errorMessage = null;
                  }),
          child: Text(
            'Voltar e corrigir dados do aluno',
            style: GoogleFonts.inter(
              color: const Color(0xFF7C4D7E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCpfOrPinStep() {
    if (_stepIndex == 2) {
      return Form(
        key: _cpfFormKey,
        child: Column(
          key: const ValueKey('guardian_step_cpf'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SelectedGuardianSummary(guardian: _selectedGuardian),
            SizedBox(height: 16.h),
            CustomTextFormField(
              controller: _cpfController,
              hintText: 'Confirme o CPF completo',
              icon: Icons.badge_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [_cpfFormatter],
              validator: (value) {
                if (_cpfFormatter.getUnmaskedText().length != 11) {
                  return 'Informe o CPF completo do responsável.';
                }
                return null;
              },
            ),
            SizedBox(height: 22.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                              _stepIndex = 1;
                              _errorMessage = null;
                            }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E1E1E),
                      side: const BorderSide(color: Color(0xFFD0D4DC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: const Text('Voltar'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _PrimaryActionButton(
                    label: 'Validar CPF',
                    isLoading: _isLoading,
                    onPressed: _verifyGuardian,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final requiresExistingPin =
        _verificationResult?.requiresExistingPin ?? false;

    return Form(
      key: _pinFormKey,
      child: Column(
        key: const ValueKey('guardian_step_pin'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectedGuardianSummary(guardian: _selectedGuardian),
          SizedBox(height: 16.h),
          _InfoCard(
            icon: Icons.lock_outline_rounded,
            title:
                requiresExistingPin ? 'Confirme seu PIN atual' : 'Crie seu PIN',
            description: requiresExistingPin
                ? 'Encontramos uma conta ativa para este CPF. Informe o PIN já cadastrado para vincular este aluno.'
                : 'Use 6 dígitos numéricos. Esse PIN será usado no próximo login junto com o CPF.',
          ),
          SizedBox(height: 16.h),
          CustomTextFormField(
            controller: _pinController,
            hintText: requiresExistingPin
                ? 'PIN atual de 6 dígitos'
                : 'PIN de 6 dígitos',
            icon: Icons.pin_outlined,
            isPassword: true,
            obscureText: !_isPinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onToggleVisibility: () {
              setState(() => _isPinVisible = !_isPinVisible);
            },
            validator: (value) {
              if ((value ?? '').trim().length != 6) {
                return requiresExistingPin
                    ? 'Informe o PIN atual com 6 dígitos.'
                    : 'O PIN precisa ter 6 dígitos.';
              }
              return null;
            },
          ),
          if (!requiresExistingPin) ...[
            SizedBox(height: 16.h),
            CustomTextFormField(
              controller: _confirmPinController,
              hintText: 'Confirme o PIN',
              icon: Icons.verified_user_outlined,
              isPassword: true,
              obscureText: !_isConfirmPinVisible,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onToggleVisibility: () {
                setState(() => _isConfirmPinVisible = !_isConfirmPinVisible);
              },
              validator: (value) {
                if ((value ?? '').trim().length != 6) {
                  return 'Repita o PIN com 6 dígitos.';
                }
                if ((value ?? '').trim() != _pinController.text.trim()) {
                  return 'Os PINs precisam ser iguais.';
                }
                return null;
              },
            ),
          ],
          SizedBox(height: 22.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _stepIndex = 2;
                            _errorMessage = null;
                          }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E1E1E),
                    side: const BorderSide(color: Color(0xFFD0D4DC)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: const Text('Voltar'),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _PrimaryActionButton(
                  label: requiresExistingPin ? 'Vincular aluno' : 'Criar PIN',
                  isLoading: _isLoading,
                  onPressed: _submitGuardianPinStep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    final resultStatus = _pinResult?.status ?? '';
    final isExistingAccountFlow = resultStatus == 'student_linked' ||
        resultStatus == 'student_already_linked';
    final successTitle = resultStatus == 'student_already_linked'
        ? 'Aluno já disponível'
        : 'Próximo login';
    final successHeadline =
        isExistingAccountFlow ? 'CPF + PIN atual' : 'CPF + PIN';
    final successBody = resultStatus == 'student_already_linked'
        ? 'Este aluno já estava vinculado à sua conta. Volte ao login e entre com o CPF e o PIN atual.'
        : isExistingAccountFlow
            ? 'Volte para a tela de login e use seu CPF com o PIN que você já utiliza nessa conta.'
            : 'Volte para a tela de login e use seu CPF com o PIN que acabou de criar.';

    return Column(
      key: const ValueKey('guardian_step_success'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InlineFeedback(
          message: _pinResult?.message ?? 'Acesso criado com sucesso.',
          isError: false,
        ),
        SizedBox(height: 18.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(18.r),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                successTitle,
                style: GoogleFonts.inter(
                  color: const Color(0xFF8B8D96),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                successHeadline,
                style: TextStyle(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 26.sp,
                  fontFamily: 'GR Milesons Three',
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Identificador cadastrado: ${_pinResult?.identifierMasked ?? '--'}',
                style: GoogleFonts.inter(
                  color: const Color(0xFF4A4F59),
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                successBody,
                style: GoogleFonts.inter(
                  color: const Color(0xFF6F7480),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 22.h),
        _PrimaryActionButton(
          label: 'Usar no login',
          isLoading: false,
          onPressed: () {
            Navigator.of(context).pop(
              _GuardianFirstAccessOutcome(
                cpfDigits: _cpfFormatter.getUnmaskedText(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LoginModeSwitch extends StatelessWidget {
  final _LoginMode currentMode;
  final ValueChanged<_LoginMode> onChanged;

  const _LoginModeSwitch({
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              label: 'Equipe / Aluno',
              isSelected: currentMode == _LoginMode.standard,
              onTap: () => onChanged(_LoginMode.standard),
            ),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: _ModeSegment(
              label: 'Responsável',
              isSelected: currentMode == _LoginMode.guardian,
              onTap: () => onChanged(_LoginMode.guardian),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999.r),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 10.w),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E1E1E) : Colors.transparent,
          borderRadius: BorderRadius.circular(999.r),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : const Color(0xFF616675),
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: const BoxDecoration(
              color: Color(0xFFF6E8F6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF7C4D7E)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF1E1E1E),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6F7480),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianStepHeader extends StatelessWidget {
  final int currentStep;

  const _GuardianStepHeader({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['Aluno', 'Vínculo', 'CPF', 'PIN', 'Sucesso'];

    return Row(
      children: List.generate(labels.length, (index) {
        final isActive = index <= currentStep;

        return Expanded(
          child: Padding(
            padding:
                EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 5.h,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFDDA0DD)
                        : const Color(0xFFD9DEE7),
                    borderRadius: BorderRadius.circular(99.r),
                  ),
                ),
                SizedBox(height: 8.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: isActive
                          ? const Color(0xFF7C4D7E)
                          : const Color(0xFF9AA0AE),
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _GuardianChoiceTile extends StatelessWidget {
  final GuardianCandidate guardian;
  final bool isSelected;
  final VoidCallback onTap;

  const _GuardianChoiceTile({
    required this.guardian,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(18.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFDDA0DD)
                  : const Color(0xFFE1E4EA),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guardian.displayName,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF1E1E1E),
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      guardian.relationship,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF727887),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? const Color(0xFF7C4D7E)
                    : const Color(0xFFB2B6C2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardianSchoolChoiceTile extends StatelessWidget {
  final GuardianSchoolOption school;
  final bool isSelected;
  final VoidCallback onTap;

  const _GuardianSchoolChoiceTile({
    required this.school,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(18.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFDDA0DD)
                  : const Color(0xFFE1E4EA),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  school.schoolName,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF1E1E1E),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? const Color(0xFF7C4D7E)
                    : const Color(0xFFB2B6C2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardianSchoolSelectorSheet extends StatelessWidget {
  final String title;
  final String message;
  final List<GuardianSchoolOption> candidateSchools;

  const _GuardianSchoolSelectorSheet({
    required this.title,
    required this.message,
    required this.candidateSchools,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 56.w,
                  height: 5.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD2D7DF),
                    borderRadius: BorderRadius.circular(99.r),
                  ),
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 20.sp,
                  fontFamily: 'GR Milesons Three',
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                message,
                style: GoogleFonts.inter(
                  color: const Color(0xFF6F7480),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              SizedBox(height: 18.h),
              ...candidateSchools.map(
                (school) => Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: _GuardianSchoolChoiceTile(
                    school: school,
                    isSelected: false,
                    onTap: () => Navigator.of(context).pop(school),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedGuardianSummary extends StatelessWidget {
  final GuardianCandidate? guardian;

  const _SelectedGuardianSummary({required this.guardian});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vínculo selecionado',
            style: GoogleFonts.inter(
              color: const Color(0xFF8B8D96),
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            guardian?.displayName ?? '--',
            style: GoogleFonts.inter(
              color: const Color(0xFF1E1E1E),
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            guardian?.relationship ?? 'Responsável',
            style: GoogleFonts.inter(
              color: const Color(0xFF6F7480),
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFeedback extends StatelessWidget {
  final String message;
  final bool isError;

  const _InlineFeedback({
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEFEF) : const Color(0xFFEDF8F0),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isError ? const Color(0xFFFFD1D1) : const Color(0xFFC9E9D3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color:
                    isError ? const Color(0xFF9D1D1D) : const Color(0xFF2D5D32),
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 22.h,
                width: 22.h,
                child: const CircularProgressIndicator(
                  color: Color(0xFFDDA0DD),
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class CustomTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isPassword;
  final bool obscureText;
  final VoidCallback? onToggleVisibility;
  final String? Function(String?)? validator;
  final IconData? icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final VoidCallback? onTap;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  const CustomTextFormField({
    super.key,
    required this.controller,
    required this.hintText,
    this.isPassword = false,
    this.obscureText = false,
    this.onToggleVisibility,
    this.validator,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    const fillColor = Colors.white;
    const hintColor = Color(0xFFA6A8A9);
    const textColor = Color(0xFF333333);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(6.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3F000000),
            blurRadius: 8,
            offset: Offset(0, 0),
            spreadRadius: -2,
          )
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        readOnly: readOnly,
        onTap: onTap,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        style: GoogleFonts.inter(
          fontSize: 16.sp,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        decoration: InputDecoration(
          counterText: '',
          prefixIcon:
              icon != null ? Icon(icon, color: hintColor, size: 23.sp) : null,
          prefixIconConstraints: BoxConstraints(minWidth: 40.w),
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: hintColor,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14.h),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    obscureText ? PhosphorIcons.eye_slash : PhosphorIcons.eye,
                    color: hintColor,
                    size: 20.sp,
                  ),
                )
              : readOnly
                  ? Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: hintColor,
                      size: 22.sp,
                    )
                  : null,
        ),
        validator: validator,
      ),
    );
  }
}

class _GuardianFirstAccessOutcome {
  final String cpfDigits;

  const _GuardianFirstAccessOutcome({
    required this.cpfDigits,
  });
}
