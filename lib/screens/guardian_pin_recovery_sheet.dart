import 'package:academyhub_mobile/model/guardian_auth_model.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';

class GuardianPinRecoveryOutcome {
  final String cpfDigits;

  const GuardianPinRecoveryOutcome({required this.cpfDigits});
}

class GuardianPinRecoverySheet extends StatefulWidget {
  const GuardianPinRecoverySheet({super.key});

  @override
  State<GuardianPinRecoverySheet> createState() =>
      _GuardianPinRecoverySheetState();
}

class _GuardianPinRecoverySheetState extends State<GuardianPinRecoverySheet> {
  static const _genericError =
      'Não foi possível confirmar os dados informados. Revise e tente novamente ou procure a escola.';
  static const _limitError =
      'Não foi possível continuar agora. Aguarde alguns minutos e tente novamente.';
  static const _restartError =
      'A recuperação foi reiniciada por segurança. Confirme os dados novamente para definir o novo PIN.';
  static const _temporaryError =
      'Não foi possível atualizar o PIN agora. Tente novamente em alguns instantes.';

  final _identityFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _cpfController = TextEditingController();
  final _studentNameController = TextEditingController();
  final _studentBirthDateController = TextEditingController();
  final _guardianBirthDateController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _cpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {'#': RegExp(r'\d')},
  );

  DateTime? _studentBirthDate;
  DateTime? _guardianBirthDate;
  bool _isLoading = false;
  bool _isPinVisible = false;
  bool _isConfirmPinVisible = false;
  int _step = 0;
  String? _errorMessage;
  String? _challengeId;
  String? _verificationToken;
  List<GuardianSchoolOption> _schoolOptions = const [];
  GuardianSchoolOption? _selectedSchool;
  GuardianPinRecoveryResult? _result;

  @override
  void initState() {
    super.initState();
    _cpfController.addListener(_invalidateSchoolSelection);
    _studentNameController.addListener(_invalidateSchoolSelection);
  }

  void _invalidateSchoolSelection() {
    if (_schoolOptions.isEmpty || !mounted || _isLoading) return;
    setState(() {
      _schoolOptions = const [];
      _selectedSchool = null;
      _errorMessage = null;
    });
  }

  String _apiDate(DateTime? value) =>
      value == null ? '' : DateFormat('yyyy-MM-dd').format(value);

  Future<void> _pickDate({required bool student}) async {
    if (_isLoading) return;
    final now = DateTime.now();
    final current = student ? _studentBirthDate : _guardianBirthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ??
          DateTime(now.year - (student ? 10 : 35), now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (student) {
        _studentBirthDate = picked;
        _studentBirthDateController.text =
            DateFormat('dd/MM/yyyy').format(picked);
      } else {
        _guardianBirthDate = picked;
        _guardianBirthDateController.text =
            DateFormat('dd/MM/yyyy').format(picked);
      }
      _schoolOptions = const [];
      _selectedSchool = null;
      _errorMessage = null;
    });
  }

  Future<void> _startRecovery() async {
    if (_isLoading || !(_identityFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_studentBirthDate == null || _guardianBirthDate == null) {
      setState(() => _errorMessage = _genericError);
      return;
    }
    if (_schoolOptions.isNotEmpty && _selectedSchool == null) {
      setState(() => _errorMessage = 'Selecione a escola para continuar.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response =
          await context.read<AuthProvider>().startGuardianPinRecovery(
                cpf: _cpfFormatter.getUnmaskedText(),
                studentFullName: _studentNameController.text.trim(),
                studentBirthDate: _apiDate(_studentBirthDate),
                guardianBirthDate: _apiDate(_guardianBirthDate),
                schoolPublicId: _selectedSchool?.schoolPublicId,
              );
      if (!mounted) return;

      if (response.schoolSelectionRequired) {
        setState(() {
          _schoolOptions = response.options;
          _selectedSchool = null;
          _challengeId = null;
          _verificationToken = null;
        });
        return;
      }

      if (!response.isReadyForPin) {
        setState(() => _errorMessage = _genericError);
        return;
      }

      setState(() {
        _challengeId = response.challengeId;
        _verificationToken = response.verificationToken;
        _schoolOptions = const [];
        _selectedSchool = null;
        _pinController.clear();
        _confirmPinController.clear();
        _step = 1;
      });
    } on GuardianPinRecoveryException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.isRateLimited ? _limitError : _genericError;
      });
    } catch (_) {
      if (mounted) setState(() => _errorMessage = _genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _returnToIdentity() {
    if (_isLoading) return;
    setState(() {
      _challengeId = null;
      _verificationToken = null;
      _pinController.clear();
      _confirmPinController.clear();
      _errorMessage = null;
      _step = 0;
    });
  }

  void _restartRecovery(String message) {
    setState(() {
      _challengeId = null;
      _verificationToken = null;
      _pinController.clear();
      _confirmPinController.clear();
      _step = 0;
      _errorMessage = message;
    });
  }

  Future<void> _completeRecovery() async {
    if (_isLoading || !(_pinFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response =
          await context.read<AuthProvider>().completeGuardianPinRecovery(
                challengeId: _challengeId!,
                verificationToken: _verificationToken!,
                newPin: _pinController.text,
              );
      if (!mounted) return;
      if (!response.isSuccess) {
        setState(() => _errorMessage = _genericError);
        return;
      }

      setState(() {
        _result = response;
        _verificationToken = null;
        _pinController.clear();
        _confirmPinController.clear();
        _step = 2;
      });
    } on GuardianPinRecoveryException catch (error) {
      if (!mounted) return;
      if (error.isExpired) {
        _restartRecovery(
          'O prazo para recuperação expirou. Confirme seus dados novamente.',
        );
      } else if (error.requiresRestart) {
        _restartRecovery(_restartError);
      } else {
        setState(() {
          _errorMessage = error.isRateLimited
              ? _limitError
              : error.isTemporarilyUnavailable
                  ? _temporaryError
                  : _genericError;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = _genericError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _cpfController.removeListener(_invalidateSchoolSelection);
    _studentNameController.removeListener(_invalidateSchoolSelection);
    _cpfController.dispose();
    _studentNameController.dispose();
    _studentBirthDateController.dispose();
    _guardianBirthDateController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Material(
          color: const Color(0xFFF7F4F8),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD2D7DF),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recuperar acesso',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF1E1E1E),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Confirme seus dados para definir um novo PIN.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF60646F),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar recuperação',
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (index) {
              final active = index <= _step;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF7C4D7E)
                        : const Color(0xFFD9D9DF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _buildIdentityStep(),
      1 => _buildPinStep(),
      _ => _buildSuccessStep(),
    };
  }

  Widget _buildIdentityStep() {
    return Form(
      key: _identityFormKey,
      child: Column(
        key: const ValueKey('pin_recovery_identity'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFeedback(),
          _field(
            controller: _cpfController,
            label: 'CPF do responsável',
            icon: Icons.badge_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [_cpfFormatter],
            validator: (_) => _cpfFormatter.getUnmaskedText().length == 11
                ? null
                : 'Informe o CPF completo.',
          ),
          const SizedBox(height: 16),
          _field(
            controller: _studentNameController,
            label: 'Nome completo do aluno',
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Informe o nome completo do aluno.'
                : null,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _studentBirthDateController,
            label: 'Data de nascimento do aluno',
            icon: Icons.calendar_month_outlined,
            readOnly: true,
            onTap: () => _pickDate(student: true),
            validator: (_) => _studentBirthDate == null
                ? 'Selecione a data de nascimento do aluno.'
                : null,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _guardianBirthDateController,
            label: 'Data de nascimento do responsável',
            icon: Icons.event_available_outlined,
            readOnly: true,
            onTap: () => _pickDate(student: false),
            validator: (_) => _guardianBirthDate == null
                ? 'Selecione a data de nascimento do responsável.'
                : null,
          ),
          if (_schoolOptions.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Selecione a escola',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E1E1E),
              ),
            ),
            const SizedBox(height: 10),
            ..._schoolOptions.map(
              (school) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: _isLoading
                      ? null
                      : () => setState(() {
                            _selectedSchool = school;
                            _errorMessage = null;
                          }),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selectedSchool?.schoolPublicId ==
                                school.schoolPublicId
                            ? const Color(0xFF7C4D7E)
                            : const Color(0xFFE0DCE2),
                        width: _selectedSchool?.schoolPublicId ==
                                school.schoolPublicId
                            ? 2
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedSchool?.schoolPublicId ==
                                  school.schoolPublicId
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: const Color(0xFF7C4D7E),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            school.schoolName,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.school_outlined,
                          color: Color(0xFF60646F),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _actionButton(
            label: _schoolOptions.isEmpty ? 'Confirmar dados' : 'Continuar',
            onPressed: _startRecovery,
          ),
        ],
      ),
    );
  }

  Widget _buildPinStep() {
    return Form(
      key: _pinFormKey,
      child: Column(
        key: const ValueKey('pin_recovery_pin'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFeedback(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0DCE2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_reset_rounded, color: Color(0xFF7C4D7E)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use exatamente 6 dígitos. Após a atualização, entre novamente com seu CPF e o novo PIN.',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4A4F59),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _field(
            controller: _pinController,
            label: 'Novo PIN',
            icon: Icons.pin_outlined,
            obscureText: !_isPinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            suffixIcon: IconButton(
              tooltip: _isPinVisible ? 'Ocultar PIN' : 'Mostrar PIN',
              onPressed: () => setState(() => _isPinVisible = !_isPinVisible),
              icon: Icon(
                _isPinVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : 'O PIN deve ter exatamente 6 dígitos.',
          ),
          const SizedBox(height: 16),
          _field(
            controller: _confirmPinController,
            label: 'Confirme o novo PIN',
            icon: Icons.verified_user_outlined,
            obscureText: !_isConfirmPinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            suffixIcon: IconButton(
              tooltip: _isConfirmPinVisible
                  ? 'Ocultar confirmação'
                  : 'Mostrar confirmação',
              onPressed: () => setState(
                () => _isConfirmPinVisible = !_isConfirmPinVisible,
              ),
              icon: Icon(
                _isConfirmPinVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            validator: (value) {
              if (!RegExp(r'^\d{6}$').hasMatch(value ?? '')) {
                return 'Repita o PIN com 6 dígitos.';
              }
              return value == _pinController.text
                  ? null
                  : 'Os PINs precisam ser iguais.';
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _returnToIdentity,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  label: 'Atualizar PIN',
                  onPressed: _completeRecovery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey('pin_recovery_success'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F8F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB8D9C0)),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF2E7D45),
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'PIN atualizado',
                style: GoogleFonts.inter(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _result?.message ??
                    'PIN atualizado. Entre novamente com seu CPF e o novo PIN.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: const Color(0xFF4A4F59),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _actionButton(
          label: 'Voltar ao login',
          onPressed: () => Navigator.of(context).pop(
            GuardianPinRecoveryOutcome(
              cpfDigits: _cpfFormatter.getUnmaskedText(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedback() {
    if (_errorMessage == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2B8B8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFF9B2C2C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                color: const Color(0xFF7A1F1F),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
    bool obscureText = false,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_isLoading,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      style: GoogleFonts.inter(
        color: const Color(0xFF1E1E1E),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          color: const Color(0xFF60646F),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: const Color(0xFF7C4D7E),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF60646F)),
        suffixIcon: suffixIcon,
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD6D1D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD6D1D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7C4D7E), width: 2),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF8A8A8A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
