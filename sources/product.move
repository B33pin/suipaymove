module suipay::product;

use std::string::{String, utf8};
use sui::event;
use sui::table::{Self, Table};
use suipay::suipay::SuiPayTreasury;

public struct PRODUCT has drop {}

public struct ProductRegistry has key, store {
    id: UID,
    merchants: Table<address, vector<address>>, //address of a merchant and list of associated pid. Would be useful in case of centralized system failure.address
}

public enum ProductType has copy, drop, store {
    Recurrent,
    OneTime,
}

public struct Subscribers has drop, store { id: address, ref_id: String, lastPaidOn: u64 }

public struct ProductSubscribersRegistry has key, store {
    id: UID,
    subscribers: Table<address, Subscribers>,
}

public struct ProductCreationEvent has copy, drop {
    productId: address,
    name: String,
    price: u64,
    owner: address,
    productType: String,
    recurringPeriod: u64,
    subscribersRegistry: address,
}

fun init(_: PRODUCT, ctx: &mut TxContext) {
    let merchants = table::new<address, vector<address>>(ctx);
    let productRegistry = ProductRegistry {
        id: object::new(ctx),
        merchants: merchants,
    };
    transfer::public_share_object(productRegistry);
}

public struct Product has key, store {
    id: UID,
    name: String,
    price: u64,
    owner: address,
    ownerWallet: address,
    productType: ProductType,
    recurringPeriod: u64,
    subscribersRegistry: address,
}

public fun getProductRegistryAddress(registry: &ProductSubscribersRegistry): address {
    object::uid_to_address(&registry.id)
}

public fun getRegistryAddress(product: &Product): address {
    product.subscribersRegistry
}

public fun getProductOwnerAddress(product: &Product): address {
    product.owner
}

public fun getProductName(product: &Product): String {
    product.name
}

public fun getProductOwnerWalletAddress(product: &Product): address {
    product.ownerWallet
}

public fun getProductId(product: &Product): address {
    object::uid_to_address(&product.id)
}

public fun getProductAmount(product: &Product): u64 {
    product.price
}

public fun getProductRenewalPeriod(product: &Product): u64 {
    product.recurringPeriod
}

public(package) fun addSubToProductRegstry(
    registry: &mut ProductSubscribersRegistry,
    subscriber: address,
    ref_id: String,
    lastPaidOn: u64,
) {
    let sub = Subscribers {
        id: subscriber,
        ref_id: ref_id,
        lastPaidOn: lastPaidOn,
    };

    let subexists = table::contains(&registry.subscribers, subscriber);
    if (subexists) {
        let subRef = table::borrow_mut(&mut registry.subscribers, subscriber);
        subRef.ref_id = ref_id;
        subRef.lastPaidOn = lastPaidOn;
    } else {
        table::add(&mut registry.subscribers, subscriber, sub);
    }
}

public(package) fun removeSubFromProductRegistry(
    registry: &mut ProductSubscribersRegistry,
    subscriber: address,
) { let subexists = table::contains(&registry.subscribers, subscriber); if (subexists) {
        table::remove(&mut registry.subscribers, subscriber);
    } }

public entry fun createOneTimeProduct(
    name: String,
    price: u64,
    productRegistry: &mut ProductRegistry,
    ownerWallet: &SuiPayTreasury,
    ctx: &mut TxContext,
) {
    //assert if the owner is the same as tx sender
    let sender = ctx.sender();
    if (sender != ownerWallet.getSuiPayOwnerAddress()) {
        abort 7
    };
    let subscribers = table::new<address, Subscribers>(ctx);
    let productSubscriberRegistry = ProductSubscribersRegistry {
        id: object::new(ctx),
        subscribers: subscribers,
    };

    let product = Product {
        id: object::new(ctx),
        name: name,
        owner: ctx.sender(),
        ownerWallet: ownerWallet.getSuiPayWalletAddress(),
        price: price,
        recurringPeriod: 0,
        productType: ProductType::OneTime,
        subscribersRegistry: object::uid_to_address(&productSubscriberRegistry.id),
    };

    let contains = table::contains(&productRegistry.merchants, ctx.sender());
    if (contains) {
        let productsVector = table::borrow_mut(&mut productRegistry.merchants, ctx.sender());
        vector::push_back(productsVector, object::uid_to_address(&product.id));
    } else {
        let mut productsVector: vector<address> = vector::empty();
        vector::push_back(&mut productsVector, object::uid_to_address(&product.id));
        table::add(&mut productRegistry.merchants, ctx.sender(), productsVector)
    };
    event::emit(ProductCreationEvent {
        productId: object::uid_to_address(&product.id),
        name: name,
        price: price,
        owner: ctx.sender(),
        productType: utf8(b"OneTime"),
        recurringPeriod: 0,
        subscribersRegistry: object::uid_to_address(&productSubscriberRegistry.id),
    });
    transfer::public_share_object(productSubscriberRegistry);
    transfer::public_share_object(product);
}

public fun getProductType(product: &Product): ProductType {
    product.productType
}

public fun getRecurrentProductType(): ProductType {
    ProductType::Recurrent
}

public entry fun createRecurrentProduct(
    name: String,
    price: u64,
    productRegistry: &mut ProductRegistry,
    recurringPeriod: u64,
    ownerWallet: &SuiPayTreasury,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    if (sender != ownerWallet.getSuiPayOwnerAddress()) {
        abort 7
    };
    let subscribers = table::new<address, Subscribers>(ctx);
    let productSubscriberRegistry = ProductSubscribersRegistry {
        id: object::new(ctx),
        subscribers: subscribers,
    };
    let product = Product {
        id: object::new(ctx),
        name: name,
        price: price,
        owner: ctx.sender(),
        ownerWallet: ownerWallet.getSuiPayWalletAddress(),
        recurringPeriod: recurringPeriod,
        productType: ProductType::Recurrent,
        subscribersRegistry: object::uid_to_address(&productSubscriberRegistry.id),
    };
    let contains = table::contains(&productRegistry.merchants, ctx.sender());
    if (contains) {
        let productsVector = table::borrow_mut(&mut productRegistry.merchants, ctx.sender());
        vector::push_back(productsVector, object::uid_to_address(&product.id));
    } else {
        let mut productsVector: vector<address> = vector::empty();
        vector::push_back(&mut productsVector, object::uid_to_address(&product.id));
        table::add(&mut productRegistry.merchants, ctx.sender(), productsVector)
    };
    event::emit(ProductCreationEvent {
        productId: object::uid_to_address(&product.id),
        name: name,
        owner: ctx.sender(),
        price: price,
        productType: utf8(b"Recurrent"),
        recurringPeriod: recurringPeriod,
        subscribersRegistry: object::uid_to_address(&productSubscriberRegistry.id),
    });
    transfer::public_share_object(productSubscriberRegistry);
    transfer::public_share_object(product);
}
