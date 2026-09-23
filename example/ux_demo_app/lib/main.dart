// A deliberately defective demo app: the public example AND the deterministic
// regression fixture for flutter-ux-journey.
//
// Do NOT tidy this up. Every flaw below was measured in a real production
// Flutter app during the Day 1 investigation, and a demo app with clean keys
// and semantics everywhere would make the tool look like it works while hiding
// the exact failure modes every real user hits on day one.
//
//   DEFECT n: one of the six seeded defects the audit must find.
//   TRAP:     not a defect — a shape that breaks the naive implementation of
//             the audit itself (selector matching, node enumeration).
//
// The whole app has exactly one Key, on a widget the journey never taps: in the
// app we measured, 2% of 446 tap targets had one, so key selectors are an
// escape hatch, never the happy path.

import 'package:flutter/material.dart';

typedef Product = ({String name, String price, String stock, String blurb});

// Top-level and mutable because DEFECT 6 mutates it with no confirmation.
final List<Product> products = <Product>[
  (
    name: 'Walnut Side Table',
    price: '189,000 KRW',
    stock: 'Only 2 left',
    blurb: 'Solid walnut, oil finish. 45 x 45 x 50 cm.',
  ),
  (
    name: 'Oak Side Table',
    price: '164,000 KRW',
    stock: 'In stock',
    blurb: 'White oak with a water-based matte finish. 40 x 40 x 48 cm.',
  ),
  (
    name: 'Linen Floor Cushion',
    price: '72,000 KRW',
    stock: 'In stock',
    blurb: 'Washed linen cover, buckwheat hull fill.',
  ),
];

void main() => runApp(const UxDemoApp());

class UxDemoApp extends StatelessWidget {
  const UxDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UX Demo',
    // White scaffold so DEFECT 4's contrast ratio is deterministic.
    theme: ThemeData(scaffoldBackgroundColor: Colors.white),
    home: const ListScreen(),
  );
}

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  bool _promoVisible = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved items'),
        actions: <Widget>[
          // DEFECT 2: no tooltip and no semanticLabel, so this is a tappable
          // node with an empty label — invisible to a screen reader.
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          // TRAP: tooltip does NOT populate the semantics label, it lands in a
          // separate field. A matcher that reads only `label` never finds this.
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_promoVisible) _promoBanner(),
          // DEFECT 4: #DDDDDD on white is a 1.36:1 contrast ratio, far under
          // the WCAG AA floor of 4.5:1 for 13px text.
          const ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Free returns within 14 days',
                style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
              ),
            ),
          ),
          // CONTROL: correct on purpose — 48dp tall and labelled by its own
          // text. A report that flags everything is visibly wrong here.
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              child: const Text('View cart (3 items)'),
            ),
          ),
          const SizedBox(height: 16),
          for (final Product p in products) _productCard(context, p),
        ],
      ),
    );
  }

  Widget _promoBanner() {
    return ColoredBox(
      color: Colors.white,
      child: Row(
        children: <Widget>[
          Expanded(
            // TRAP: InkWell gives this a tap action but never the isButton
            // flag, so enumeration has to key off the action, not the flag.
            child: InkWell(
              onTap: () {},
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14), // 48dp tall: not a defect
                child: Text('Autumn sale — 20% off every side table'),
              ),
            ),
          ),
          // DEFECT 1: a 24x24 tap target. iOS wants 44x44, Android 48x48.
          // Labelled on purpose so the only thing wrong with it is its size.
          Semantics(
            label: 'Dismiss promotion',
            button: true,
            child: GestureDetector(
              key: const Key('promo_dismiss'),
              onTap: () => setState(() => _promoVisible = false),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.close, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(BuildContext context, Product p) {
    // DEFECT 3: the InkWell's tap action absorbs the three sibling Texts, so
    // the card is ONE node whose label is the three strings joined by '\n'.
    // Nothing here asked for that — it is what Flutter does — which is why an
    // exact-match label selector misses every card in a real app. Two names
    // also share "Side Table", so a naive substring match hits two nodes and
    // must raise ambiguity instead of taking the first.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(p))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(p.name, style: Theme.of(context).textTheme.titleMedium),
              Text(p.price),
              Text(p.stock),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailScreen extends StatelessWidget {
  const DetailScreen(this.product, {super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // CONTROL: AppBar's implied leading is a 48x48 IconButton tooltipped
      // 'Back'. This screen is not the dead end; the next one is.
      appBar: AppBar(title: Text(product.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              product.price,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(product.blurb),
            const Spacer(),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E),
                ),
                // DEFECT 6: destructive and irreversible, with no confirmation
                // step of any kind between the tap and the data loss.
                onPressed: () {
                  products.remove(product);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const RemovedScreen()),
                    (Route<void> route) => false,
                  );
                },
                child: const Text('Remove from list'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemovedScreen extends StatelessWidget {
  const RemovedScreen({super.key});

  // DEFECT 5: a dead end. No back affordance, and the push that landed here
  // cleared the whole stack, so the system back gesture has nowhere to go
  // either. Every widget on this screen passes every per-screen check; the
  // defect only exists at the journey level, where the goal is unreachable.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Removed'),
      automaticallyImplyLeading: false,
    ),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 48),
            SizedBox(height: 12),
            Text('Removed from your list', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
