import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stripe_sdk/src/ui/stores/payment_method_store.dart';

import '../../models/card.dart';
import '../../stripe.dart';
import '../models.dart';
import '../progress_bar.dart';
import '../stripe_ui.dart';
import '../widgets/card_form.dart';

///

/// A screen that collects, creates and attaches a payment method to a stripe customer.
///
/// Payment methods can be created with and without a Setup Intent. Using a Setup Intent is highly recommended.
///
class AddPaymentMethodScreen extends StatefulWidget {
  final Stripe _stripe;

  /// Used to create a setup intent when required.
  final createSetupIntent = StripeUiOptions.createSetupIntent;

  /// The payment method store used to manage payment methods.
  final PaymentMethodStore _paymentMethodStore;

  /// The card form used to collect payment method details.
  final CardForm _form;

  /// Custom Title for the screen
  final String title;
  static const String _defaultTitle = 'Add payment method';

  final Text headerText;
  final double viewPadding;
  static Route<String?> route(
      {PaymentMethodStore? paymentMethodStore,
      Stripe? stripe,
      CardForm? form,
      String title = _defaultTitle,
      Text? headerText,
      double? viewPadding}) {
    return MaterialPageRoute(
      builder: (context) => AddPaymentMethodScreen(
        paymentMethodStore: paymentMethodStore,
        stripe: stripe,
        form: form,
        title: title,
        headerText: headerText,
        viewPadding: viewPadding
      ),
    );
  }

  /// Add a payment method using a Stripe Setup Intent
  AddPaymentMethodScreen(
      {Key? key,
      PaymentMethodStore? paymentMethodStore,
      Stripe? stripe,
      CardForm? form,
      this.title = _defaultTitle,
      Text? headerText, double? viewPadding})
      : _form = form ?? CardForm(),
        _paymentMethodStore = paymentMethodStore ?? PaymentMethodStore.instance,
        _stripe = stripe ?? Stripe.instance,
        headerText = headerText ?? Text(title),
        viewPadding = viewPadding ?? 10,
        super(key: key);

  @override
  _AddPaymentMethodScreenState createState() => _AddPaymentMethodScreenState();
}

class _AddPaymentMethodScreenState extends State<AddPaymentMethodScreen> {
  late final StripeCard _cardData;
  late final GlobalKey<FormState> _formKey;

  Future<IntentClientSecret>? setupIntentFuture;

  @override
  void initState() {
    if (widget.createSetupIntent != null)
      setupIntentFuture = widget.createSetupIntent!();
    _cardData = widget._form.card;
    _formKey = widget._form.formKey;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xff223039),
          foregroundColor: const Color(0xff223039),
          leading: IconButton(
            onPressed: () => {
              Navigator.maybePop(context)
            },
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
          ),
          title: widget.headerText,
        ),
        body: Container(
          height: MediaQuery.of(context).size.height,
          padding: EdgeInsets.symmetric(horizontal: widget.viewPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              widget._form,
              // Set as default payment method, toggle
          
              // Add Card Button
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                padding: const EdgeInsets.only(top: 25),
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(
                        width: MediaQuery.of(context).size.width, height: 50),
                    child: ElevatedButton(
                      child: const Text(
                        'Add Card',
                        style: TextStyle(
                            color: Color(0xffffffff),
                            // fontFamily: headingText,
                            fontWeight: FontWeight.w600,
                            fontSize: 18),
                      ),
                      style: ButtonStyle(
                        foregroundColor:
                            MaterialStateProperty.all<Color>(Color(0xff223039)),
                        backgroundColor:
                            MaterialStateProperty.all<Color>(Color(0xff223039)),
                        shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                            const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                side: BorderSide(color: Colors.transparent))),
                      ),
                      onPressed: () async {
                        final formState = _formKey.currentState;
                        if (formState?.validate() ?? false) {
                          formState!.save();
                          await _createPaymentMethod(context, _cardData);
                        }
                      },
                    ),
                  ),
                ),
              ),
          
              if (StripeUiOptions.showTestPaymentMethods)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    children: [
                      _createTestCardButton("4242424242424242"),
                      _createTestCardButton("4000000000003220"),
                      _createTestCardButton("4000000000003063"),
                      _createTestCardButton("4000008400001629"),
                      _createTestCardButton("4000008400001280"),
                      _createTestCardButton("4000000000003055"),
                      _createTestCardButton("4000000000003097"),
                      _createTestCardButton("378282246310005"),
                    ],
                  ),
                )
            ],
          ),
        ));
  }

  Widget _createTestCardButton(String number) {
    return OutlinedButton(
        child: Text(number.substring(number.length - 4)),
        onPressed: () => _createPaymentMethod(
            context,
            StripeCard(
                number: number, cvc: "123", expMonth: 1, expYear: 2030)));
  }

  Future<void> _createPaymentMethod(
      BuildContext context, StripeCard cardData) async {
    showProgressDialog(context);
    var paymentMethod = await widget._stripe.api.createPaymentMethodFromCard(cardData);
    if (setupIntentFuture != null) {
      final initialSetupIntent = await setupIntentFuture!;
      try {
      final confirmedSetupIntent = await widget._stripe.confirmSetupIntent(
          initialSetupIntent.clientSecret, paymentMethod['id'],
          context: context);
        if (confirmedSetupIntent['status'] == 'succeeded') {
          /// A new payment method has been attached, so refresh the store.
          await widget._paymentMethodStore.refresh();
          debugPrint('Payment method successfully added');
          Navigator.pop(context, jsonEncode(paymentMethod));
          return;
        } 
        else {
          Map<String, dynamic> errorData = {
            'error': true,
            'message': 'Authentication failed'
          };
          debugPrint('Card auth failed');
          Navigator.pop(context, errorData);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Authentication failed, please try again.")));
        }
      }
      catch(e) {
        Navigator.pop(context, false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.toString())));
        print(e.toString());
      }
      /*} catch (e) {
        Map<String, dynamic> errorData = {
          'error': true,
          'message': 'Authentication failed'
        };
        debugPrint('Card auth failed');
        // hideProgressDialog(context);
        // Navigator.pop(context, errorData);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Authentication failed, please try again.")));
        debugPrint(e.toString());
      }
      hideProgressDialog(context);
    } */
        // }
    // else {
    //   paymentMethod = await (widget._paymentMethodStore
    //       .attachPaymentMethod(paymentMethod['id']));
    //   hideProgressDialog(context);
    //   Navigator.pop(context, jsonEncode(paymentMethod));
    //   return;
    // }
}
      }}
      
