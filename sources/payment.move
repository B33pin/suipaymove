module suipay::payment;

use std::ascii::String;
use sui::address;
use sui::clock::Clock;
use sui::event;
use sui::table::{Self, Table};
use suipay::product::{Self, Product, ProductSubscribersRegistry};
use suipay::suipay::{Self, SuiPayTreasury};

const ENOT_AUTHORIZED: u64 = 7;
const ESENDERNOTMATCHED: u64 = 8;
const EPRODOWNERNOTMATCHED: u64 = 9;
const EPRODUCTREGNOTMATCHED: u64 = 10;
const EPAYMENTINTENTDOESNOTEXIST: u64 = 11;

public struct PAYMENT has drop {}

public struct PaymentIntent has key, store {
    id: UID,
    owner: address,
    product: address,
    amount: u64,
    ref_id: String,
    lastPaidOn: u64,
}

public struct PaymentIntentCreationEvent has copy, drop {
    intentId: address,
    owner: address,
    productId: address,
    ref_id: String,
    amount: u64,
    lastPaidOn: u64,
}

public struct PaymentIntentDeleteEvent has copy, drop {
    intentId: address,
    owner: address,
    productId: address,
    ref_id: String,
    amount: u64,
}

public struct PaymentReceiptEvent has copy, drop {
    owner: address,
    productId: address,
    ref_id: String,
    amount: u64,
}

public struct IndividualActiveSubscriptionRegistry has key, store {
    id: UID,
    payments: Table<address, vector<address>>, //address of the user and list of payment intents
}

fun init(_: PAYMENT, ctx: &mut TxContext) {
    let merchants = table::new<address, vector<address>>(ctx);
    let productRegistry = IndividualActiveSubscriptionRegistry {
        id: object::new(ctx),
        payments: merchants,
    };
    transfer::public_share_object(productRegistry);
}

public fun makePayment(
    product: &mut Product,
    users_wallet: &mut SuiPayTreasury,
    prod_owner_wallet: &mut SuiPayTreasury,
    prod_registry: &mut ProductSubscribersRegistry,
    indiv_sub_registry: &mut IndividualActiveSubscriptionRegistry,
    ref_id: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    if (sender != users_wallet.getSuiPayOwnerAddress()) {
        abort ESENDERNOTMATCHED
    };

    if (
        (product.getProductOwnerWalletAddress()!=prod_owner_wallet.getSuiPayWalletAddress())||(product.getProductOwnerAddress()!=prod_owner_wallet.getSuiPayOwnerAddress())
    ) {
        abort EPRODOWNERNOTMATCHED
    };

    if (prod_registry.getProductRegistryAddress() != product.getRegistryAddress()) {
        abort EPRODUCTREGNOTMATCHED
    };

    let amount = product.getProductAmount();
    suipay::transferFromOneTreasuryToAnother(
        amount,
        product.getProductName(),
        users_wallet,
        prod_owner_wallet,
        clock,
        ref_id.to_string(),
        ctx,
    );
    if (product.getProductType() == product::getRecurrentProductType()) {
        let paymentIntent = PaymentIntent {
            id: object::new(ctx),
            owner: sender,
            product: product.getProductId(),
            amount: amount,
            ref_id: ref_id,
            lastPaidOn: clock.timestamp_ms(),
        };

        let paymentIntentEvent = PaymentIntentCreationEvent {
            intentId: object::uid_to_address(&paymentIntent.id),
            owner: sender,
            productId: product.getProductId(),
            ref_id: ref_id,
            amount: amount,
            lastPaidOn: clock.timestamp_ms(),
        };

        let paymentIntentAddress = object::uid_to_address(&paymentIntent.id);
        let paymentIntentListExists = table::contains(
            &indiv_sub_registry.payments,
            sender,
        );
        if (!paymentIntentListExists) {
            let mut paymentIntentList = vector::empty<address>();
            vector::push_back(&mut paymentIntentList, paymentIntentAddress);
            table::add(
                &mut indiv_sub_registry.payments,
                sender,
                paymentIntentList,
            );
        } else {
            let paymentIntentList = table::borrow_mut(&mut indiv_sub_registry.payments, sender);
            let (paymentIntentExists, _) = vector::index_of(
                paymentIntentList,
                &paymentIntentAddress,
            );
            if (!paymentIntentExists) {
                vector::push_back(paymentIntentList, paymentIntentAddress);
            };
        };
        transfer::public_share_object(paymentIntent);
        event::emit(paymentIntentEvent);
    };
    let paymentReceiptEvent = PaymentReceiptEvent {
        owner: sender,
        productId: product.getProductId(),
        ref_id: ref_id,
        amount: amount,
    };
    event::emit(paymentReceiptEvent);

    product::addSubToProductRegstry(
        prod_registry,
        sender,
        ref_id.to_string(),
        clock.timestamp_ms(),
    );
}

public fun makePaymentFromIntent(
    product: &mut Product,
    paymentIntent: &mut PaymentIntent,
    users_wallet: &mut SuiPayTreasury,
    prod_owner_wallet: &mut SuiPayTreasury,
    prod_registry: &mut ProductSubscribersRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    //need to check if the time for payment is valid or not
    //it depends on the payment intent lastPaidOn + recurringPeriod
    //sender might not be the same as the owner of the payment intent

    let time = clock.timestamp_ms();
    if (time < (paymentIntent.lastPaidOn + product.getProductRenewalPeriod())) {
        abort ENOT_AUTHORIZED
    };
    //if amount is also changed make it unauthorized
    if (paymentIntent.amount != product.getProductAmount()) {
        abort ENOT_AUTHORIZED
    };
    suipay::transferFromOneTreasuryToAnother(
        paymentIntent.amount,
        product.getProductName(),
        users_wallet,
        prod_owner_wallet,
        clock,
        paymentIntent.ref_id.to_string(),
        ctx,
    );

    let paymentReceiptEvent = PaymentReceiptEvent {
        owner: paymentIntent.owner,
        productId: product.getProductId(),
        ref_id: paymentIntent.ref_id,
        amount: paymentIntent.amount,
    };
    event::emit(paymentReceiptEvent);

    product::addSubToProductRegstry(
        prod_registry,
        paymentIntent.owner,
        paymentIntent.ref_id.to_string(),
        clock.timestamp_ms(),
    );
}

public fun unsubscribeFromProduct(
    product: &mut Product,
    paymentIntent: PaymentIntent,
    prod_registry: &mut ProductSubscribersRegistry,
    indiv_sub_registry: &mut IndividualActiveSubscriptionRegistry,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    let hotwallet = address::from_ascii_bytes(
        &b"ec7953af5b86a41e82a2af6f35c2501127a18e49d57926474efb894e0b90f0f6",
    );
    if (sender == paymentIntent.owner   || sender == hotwallet) {
        let paymentIntentDeleteEvent = PaymentIntentDeleteEvent {
            intentId: object::uid_to_address(&paymentIntent.id),
            owner: sender,
            productId: product.getProductId(),
            ref_id: paymentIntent.ref_id,
            amount: paymentIntent.amount,
        };
        let PaymentIntent {
            id,
            owner: _,
            product: _,
            amount: _,
            ref_id: _,
            lastPaidOn: _,
        } = paymentIntent;

        let paymentIntentList = table::borrow_mut(&mut indiv_sub_registry.payments, sender);
        let (paymentIntentExists, index) = vector::index_of(
            paymentIntentList,
            &object::uid_to_address(&id),
        );
        if (!paymentIntentExists) {
            abort EPAYMENTINTENTDOESNOTEXIST
        };
        vector::remove(paymentIntentList, index);
        object::delete(id);
        product::removeSubFromProductRegistry(prod_registry, sender);
        event::emit(paymentIntentDeleteEvent);
    } else {
        abort ENOT_AUTHORIZED
    }
}
