import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_card.dart';

class BerandaPage extends StatefulWidget {
  const BerandaPage({
    required this.kloter,
    required this.onOpenKloter,
    super.key,
  });

  final List<DemoKloter> kloter;
  final ValueChanged<DemoKloter> onOpenKloter;

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final status = _selected == 0 ? KloterStatus.review : KloterStatus.done;
    final recent = widget.kloter.where((item) => item.status == status).take(3);
    return CustomScrollView(
      key: const PageStorageKey('beranda-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(niraInset, 6, niraInset, 15),
          sliver: SliverList.list(
            children: const [
              _Profile(),
              SizedBox(height: 15),
              _ProductionSummary(),
              SizedBox(height: 17),
              _QuickActions(),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: niraLeaf, width: 1),
                left: BorderSide(color: niraLeaf, width: 1),
                right: BorderSide(color: niraLeaf, width: 1),
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NiraTabs(
                  labels: const ['Tinjau', 'Tuntas'],
                  selected: _selected,
                  height: 50,
                  fontSize: 14.5,
                  inset: 27,
                  wideIndicator: true,
                  onSelected: (value) => setState(() => _selected = value),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    niraInset,
                    15,
                    niraInset,
                    13,
                  ),
                  child: Column(
                    children: [
                      for (final item in recent)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: KloterCard(
                            kloter: item,
                            onTap: () => widget.onOpenKloter(item),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 57),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: niraGreen,
      borderRadius: BorderRadius.circular(33),
    ),
    child: Row(
      children: [
        ClipOval(
          child: Image.asset(
            'assets/sobatnira/art/profil-demo.png',
            width: 40,
            height: 40,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Pabrik Demo', style: niraText(10.5, color: Colors.white)),
              const SizedBox(height: 1),
              Text(
                'Admin Demo',
                style: niraText(
                  16,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => showUnavailable(context),
            child: const Tooltip(
              message: 'Notifikasi',
              child: SizedBox(
                width: 43,
                height: 43,
                child: Center(child: NiraIcon('bell', 20, color: niraGreen)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProductionSummary extends StatelessWidget {
  const _ProductionSummary();

  static const _smallStats = [
    ('Gula final', '820Kg', Icons.water_drop_outlined),
    ('Kloter', '3', Icons.layers_outlined),
    ('Antrean batch', '4', Icons.format_list_bulleted),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: niraGreen, width: 1.35),
      borderRadius: BorderRadius.circular(7),
      boxShadow: const [niraShadow],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: niraGreen,
                image: DecorationImage(
                  image: AssetImage('assets/sobatnira/art/hero-texture.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Image.asset(
                      'assets/sobatnira/art/hero-cane.png',
                      width: 153,
                      height: 103,
                      excludeFromSemantics: true,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 102),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 8, 13, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tebu diterima',
                            style: niraText(
                              17.65,
                              color: Colors.white,
                              weight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '8.200Kg',
                            style: niraText(
                              35.31,
                              color: niraYellow,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '20 Oktober 2026',
                            style: niraText(11.8, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value, icon) in _smallStats)
                Expanded(child: _SummaryTile(label, value, icon)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 55),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      gradient: const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF102E20), Color(0xFF205D42)],
      ),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: -5,
          right: 0,
          child: Icon(icon, color: const Color(0x0DFFFFFF), size: 50),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: niraText(
                  9.6,
                  color: Colors.white,
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: niraText(
                  16.5,
                  color: niraYellow,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = [
    ('Laba', 'calculator', 25.0),
    ('Biaya Ops', 'tag', 29.0),
    ('Rekap', 'clip', 26.0),
    ('Bantuan', 'headset', 32.0),
  ];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (label, icon, size) in _actions)
        Flexible(
          child: SizedBox(
            width: 63,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => showUnavailable(context),
                borderRadius: BorderRadius.circular(7),
                child: Column(
                  children: [
                    Container(
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: niraGreen, width: 1.3),
                      ),
                      child: NiraIcon(icon, size),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: niraText(
                        11.5,
                        color: Colors.black,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
