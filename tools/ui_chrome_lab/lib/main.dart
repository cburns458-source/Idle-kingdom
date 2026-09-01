import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:pixel_ui/pixel_ui.dart';

/// Standalone chrome lab. Does not import or modify RestoriaIdle game code.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UiChromeLabApp());
}

enum ChromeStyle { baseline, nesUi, pixelUi, kenneyFantasy, leather }

extension on ChromeStyle {
  String get label => switch (this) {
        ChromeStyle.baseline => 'A Baseline',
        ChromeStyle.nesUi => 'B nes_ui',
        ChromeStyle.pixelUi => 'C pixel_ui',
        ChromeStyle.kenneyFantasy => 'D Kenney CC0',
        ChromeStyle.leather => 'E Leather+noise',
      };

  String get blurb => switch (this) {
        ChromeStyle.baseline =>
          'Current language: pill radius, thin gold hairlines, sparse grain.',
        ChromeStyle.nesUi =>
          'MIT package: NesButton / NesContainer / NesProgressBar. Hard pixel chrome.',
        ChromeStyle.pixelUi =>
          'Pure pixel + max not-modern: stair corners, dense grain on every plate, chunky shadows, zero pills.',
        ChromeStyle.kenneyFantasy =>
          'CC0 9-slice fantasy panels. Every chrome role becomes a framed plate.',
        ChromeStyle.leather =>
          'Custom painters: zero pills, brass studs, grain on every surface.',
      };
}

class UiChromeLabApp extends StatelessWidget {
  const UiChromeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UI Chrome Lab',
      debugShowCheckedModeBanner: false,
      theme: flutterNesTheme(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF7F9D63),
      ),
      home: const LabHome(),
    );
  }
}

class LabHome extends StatefulWidget {
  const LabHome({super.key});

  @override
  State<LabHome> createState() => _LabHomeState();
}

class _LabHomeState extends State<LabHome> {
  ChromeStyle _style = ChromeStyle.pixelUi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A120C),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                'UI CHROME LAB',
                style: TextStyle(
                  color: Color(0xFFF4E7C8),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                'No game client code. Same shell roles remapped per kit.',
                style: TextStyle(color: Color(0xFFCBB894), fontSize: 12),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final style in ChromeStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(style.label, style: const TextStyle(fontSize: 11)),
                        selected: _style == style,
                        onSelected: (_) => setState(() => _style = style),
                        selectedColor: const Color(0xFF5F7A45),
                        backgroundColor: const Color(0xFF3D2A1A),
                        labelStyle: TextStyle(
                          color: _style == style
                              ? const Color(0xFFF4E7C8)
                              : const Color(0xFFCBB894),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Text(
                _style.blurb,
                style: const TextStyle(color: Color(0xFFCBB894), fontSize: 12, height: 1.35),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0A07),
                        border: Border.all(color: const Color(0xFF5C4027), width: 3),
                      ),
                      child: switch (_style) {
                        ChromeStyle.baseline => const _BaselineShell(),
                        ChromeStyle.nesUi => const _NesShell(),
                        ChromeStyle.pixelUi => const _PixelShell(),
                        ChromeStyle.kenneyFantasy => const _KenneyShell(),
                        ChromeStyle.leather => const _LeatherShell(),
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _BaselineShell extends StatelessWidget {
  const _BaselineShell();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2A1B12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF3D2A1A),
              border: Border(bottom: BorderSide(color: Color(0x73D4AF37))),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9EC8E8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x73D4AF37)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F9A55), Color(0xFF8FCE6B)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tester · Lv 12',
                        style: TextStyle(color: Color(0xFFF4E7C8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _pill('Menu'),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3D2A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x73D4AF37)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Meadow Road',
                      style: TextStyle(color: Color(0xFFFFE7A8), fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gather flax · 0:12',
                      style: TextStyle(color: Color(0xFFCBB894), fontSize: 13),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(child: _pillBtn('Gather', primary: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _pillBtn('Travel')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Maps to GameButton / GamePanel — radius 12–14 everywhere.',
                      style: TextStyle(color: Color(0xFF8A7A5C), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _nav(round: true),
        ],
      ),
    );
  }
}

class _NesShell extends StatelessWidget {
  const _NesShell();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF21201F),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            NesContainer(
              label: 'hero',
              child: Row(
                children: [
                  NesIcon(iconData: NesIcons.user, size: const Size.square(28)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NesProgressBar(value: 0.72),
                        SizedBox(height: 4),
                        Text('Tester  Lv12', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  NesButton.text(
                    type: NesButtonType.normal,
                    text: 'MENU',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: NesContainer(
                width: double.infinity,
                label: 'location',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('MEADOW ROAD', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    const Text('Gather flax  0:12', style: TextStyle(fontSize: 10)),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: NesButton.text(
                            type: NesButtonType.primary,
                            text: 'GATHER',
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NesButton.text(
                            type: NesButtonType.normal,
                            text: 'TRAVEL',
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final label in ['MAP', 'SKILL', 'BAG', 'SOCIAL'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: NesButton.text(
                        type: label == 'MAP' ? NesButtonType.primary : NesButtonType.normal,
                        text: label,
                        onPressed: () {},
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Covers buttons, panels, tabs, dialogs, bars. Gap: ornate fantasy frames.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Color(0xFFAAA08C)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelShell extends StatelessWidget {
  const _PixelShell();

  /// Pure pixel + max not-modern: sharp stairs, dense grain, hard shadows.
  static const panel = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF2E1C10),
    borderColor: Color(0xFFF0E0B8),
    borderWidth: 3,
    shadow: PixelShadow(
      offset: Offset(3, 3),
      color: Color(0xEE000000),
    ),
    texture: PixelTexture(
      color: Color(0x55FFFFFF),
      density: 0.42,
      size: 1,
      seed: 17,
    ),
  );

  static const inset = PixelShapeStyle(
    corners: PixelCorners.md,
    fillColor: Color(0xFF24160E),
    borderColor: Color(0xFFC9B07A),
    borderWidth: 2,
    texture: PixelTexture(
      color: Color(0x44FFFFFF),
      density: 0.38,
      size: 1,
      seed: 29,
    ),
  );

  static const btn = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF5F7A45),
    borderColor: Color(0xFFF0E0B8),
    borderWidth: 3,
    shadow: PixelShadow(
      offset: Offset(3, 3),
      color: Color(0xDD000000),
    ),
    texture: PixelTexture(
      color: Color(0x33000000),
      density: 0.28,
      size: 1,
      seed: 3,
    ),
  );

  static const btnAlt = PixelShapeStyle(
    corners: PixelCorners.lg,
    fillColor: Color(0xFF5A3A22),
    borderColor: Color(0xFFE0C878),
    borderWidth: 3,
    shadow: PixelShadow(
      offset: Offset(3, 3),
      color: Color(0xDD000000),
    ),
    texture: PixelTexture(
      color: Color(0x33000000),
      density: 0.28,
      size: 1,
      seed: 7,
    ),
  );

  static const portrait = PixelShapeStyle(
    corners: PixelCorners.sm,
    fillColor: Color(0xFF6A8FA8),
    borderColor: Color(0xFFF0E0B8),
    borderWidth: 3,
    shadow: PixelShadow(
      offset: Offset(2, 2),
      color: Color(0xCC000000),
    ),
    texture: PixelTexture(
      color: Color(0x22000000),
      density: 0.2,
      size: 1,
      seed: 5,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF140E0A),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            PixelBox(
              logicalWidth: 48,
              logicalHeight: 16,
              width: double.infinity,
              height: 72,
              style: panel,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  PixelBox(
                    logicalWidth: 10,
                    logicalHeight: 10,
                    width: 42,
                    height: 42,
                    style: portrait,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'TESTER  LV12',
                          style: TextStyle(
                            color: Color(0xFFF0E0B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'HP ████████░░',
                          style: TextStyle(
                            color: Color(0xFF8FCE6B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PixelBox(
                logicalWidth: 48,
                logicalHeight: 40,
                width: double.infinity,
                height: double.infinity,
                style: panel,
                label: const Text(
                  'MEADOW ROAD',
                  style: TextStyle(
                    color: Color(0xFFF0E0B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PixelBox(
                        logicalWidth: 40,
                        logicalHeight: 18,
                        width: double.infinity,
                        height: double.infinity,
                        style: inset,
                        padding: const EdgeInsets.all(10),
                        alignment: Alignment.topLeft,
                        child: const Text(
                          'Gather flax\n0:12 remaining\n\nGrain on every plate.\nNo pills. No hairlines.',
                          style: TextStyle(
                            color: Color(0xFFD2C09A),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: PixelButton(
                            logicalWidth: 20,
                            logicalHeight: 9,
                            height: 40,
                            normalStyle: btn,
                            pressedStyle: btn.copyWith(
                              fillColor: const Color(0xFF4A6234),
                            ),
                            pressChildOffset: const Offset(0, 2),
                            onPressed: () {},
                            child: const Text(
                              'GATHER',
                              style: TextStyle(
                                color: Color(0xFFF0E0B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PixelButton(
                            logicalWidth: 20,
                            logicalHeight: 9,
                            height: 40,
                            normalStyle: btnAlt,
                            pressedStyle: btnAlt.copyWith(
                              fillColor: const Color(0xFF452A18),
                            ),
                            pressChildOffset: const Offset(0, 2),
                            onPressed: () {},
                            child: const Text(
                              'TRAVEL',
                              style: TextStyle(
                                color: Color(0xFFF0E0B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final label in ['MAP', 'SKILL', 'BAG', 'SOCIAL'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: PixelButton(
                        logicalWidth: 12,
                        logicalHeight: 9,
                        height: 40,
                        normalStyle: label == 'MAP' ? btn : btnAlt,
                        pressChildOffset: const Offset(0, 2),
                        onPressed: () {},
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFFF0E0B8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'pixel_ui · stair corners · dense LCG grain · hard shadows · zero modern chrome',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A7A5C), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _KenneyShell extends StatelessWidget {
  const _KenneyShell();

  static const panel = 'assets/panels/panel-008.png';
  static const plate = 'assets/panels/panel-transparent-center-008.png';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF24180F)),
        const Opacity(
          opacity: 0.32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/noise.png'),
                repeat: ImageRepeat.repeat,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _Nine(
                asset: plate,
                height: 70,
                child: const Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: ColoredBox(color: Color(0xFF6A8FA8)),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tester · Lv 12\nHP ###########---',
                        style: TextStyle(color: Color(0xFFF4E7C8), fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _Nine(
                  asset: panel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Meadow Road',
                        style: TextStyle(color: Color(0xFFFFE7A8), fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Gather flax · 0:12',
                        style: TextStyle(color: Color(0xFFCBB894), fontSize: 12),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(child: _NineBtn('Gather', plate)),
                          const SizedBox(width: 8),
                          Expanded(child: _NineBtn('Travel', plate)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final label in ['Map', 'Skills', 'Bag', 'Social'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _NineBtn(label, plate, compact: true),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Covers panels via 9-slice. Rework: buttons/nav/HUD all as framed plates.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8A7A5C), fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeatherShell extends StatelessWidget {
  const _LeatherShell();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _LeatherBg()),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _StudPlate(
                height: 68,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A4A30),
                        border: Border.all(color: const Color(0xFFC9A227), width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Tester · leather HUD\nHP ###########---',
                        style: TextStyle(color: Color(0xFFF4E7C8), fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _StudPlate(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Meadow Road',
                        style: TextStyle(color: Color(0xFFFFE7A8), fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Parchment inset · noise on every panel',
                        style: TextStyle(color: Color(0xFFCBB894), fontSize: 12),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(child: _Stamp('GATHER', primary: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _Stamp('TRAVEL')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final label in ['MAP', 'SKILL', 'BAG', 'SOCIAL'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _Stamp(label, primary: label == 'MAP', compact: true),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Full chrome coverage with one plate language. No package dependency.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8A7A5C), fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Nine extends StatelessWidget {
  const _Nine({required this.asset, required this.child, this.height});
  final String asset;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(asset),
            centerSlice: const Rect.fromLTRB(32, 32, 64, 64),
            filterQuality: FilterQuality.none,
            fit: BoxFit.fill,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: child,
        ),
      ),
    );
  }
}

class _NineBtn extends StatelessWidget {
  const _NineBtn(this.label, this.asset, {this.compact = false});
  final String label;
  final String asset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 36 : 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(asset),
            centerSlice: const Rect.fromLTRB(32, 32, 64, 64),
            filterQuality: FilterQuality.none,
            fit: BoxFit.fill,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFFF4E7C8),
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _StudPlate extends StatelessWidget {
  const _StudPlate({required this.child, this.height});
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _StudPainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: child,
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.label, {this.primary = false, this.compact = false});
  final String label;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 34 : 40,
      child: CustomPaint(
        painter: _StampPainter(primary: primary),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFFF4E7C8),
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _StudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF4A2F1C));
    canvas.drawRect(
      rect.deflate(1.5),
      Paint()
        ..color = const Color(0xFFC9A227)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRect(
      rect.deflate(5),
      Paint()
        ..color = const Color(0xFF2A1B12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final stud = Paint()..color = const Color(0xFFD4AF37);
    for (final p in [
      const Offset(8, 8),
      Offset(size.width - 8, 8),
      Offset(8, size.height - 8),
      Offset(size.width - 8, size.height - 8),
    ]) {
      canvas.drawCircle(p, 3, stud);
    }
    _noise(canvas, size, 0.12);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.primary});
  final bool primary;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = primary ? const Color(0xFF5A7040) : const Color(0xFF5C3A22),
    );
    canvas.drawRect(
      rect.deflate(1.5),
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _noise(canvas, size, 0.16);
  }

  @override
  bool shouldRepaint(covariant _StampPainter oldDelegate) => oldDelegate.primary != primary;
}

class _LeatherBg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A1810));
    _noise(canvas, size, 0.22);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _noise(Canvas canvas, Size size, double density) {
  final rng = math.Random(42);
  final paint = Paint();
  final count = (size.width * size.height * density * 0.04).round();
  for (var i = 0; i < count; i++) {
    final x = rng.nextDouble() * size.width;
    final y = rng.nextDouble() * size.height;
    final v = rng.nextInt(80);
    paint.color = Color.fromARGB(28 + rng.nextInt(40), v, v, v);
    canvas.drawRect(Rect.fromLTWH(x, y, 1.2, 1.2), paint);
  }
}

Widget _pill(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF6A4A30),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x73D4AF37)),
    ),
    child: Text(label, style: const TextStyle(color: Color(0xFFF4E7C8), fontSize: 11)),
  );
}

Widget _pillBtn(String label, {bool primary = false}) {
  return Container(
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: primary
            ? const [Color(0xFF7F9D63), Color(0xFF5F7A45)]
            : const [Color(0xFF6A4A30), Color(0xFF45301F)],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x73D4AF37)),
    ),
    child: Text(label, style: const TextStyle(color: Color(0xFFF4E7C8))),
  );
}

Widget _nav({required bool round}) {
  const labels = ['Map', 'Skills', 'Bag', 'Social'];
  return Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
    decoration: const BoxDecoration(
      color: Color(0xFF3D2A1A),
      border: Border(top: BorderSide(color: Color(0x73D4AF37))),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Container(
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == 0 ? const Color(0xFF5F7A45) : const Color(0xFF6A4A30),
                borderRadius: BorderRadius.circular(round ? 12 : 0),
                border: Border.all(color: const Color(0x73D4AF37)),
              ),
              child: Text(
                labels[i],
                style: const TextStyle(color: Color(0xFFF4E7C8), fontSize: 11),
              ),
            ),
          ),
      ],
    ),
  );
}
