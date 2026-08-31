<template>
  <div class="cart">
    <div class="page-head">
      <div>
        <p class="eyebrow">Comptoir</p>
        <h2>Panier</h2>
      </div>
      <p class="meta">{{ cartItems.length }} ligne{{ cartItems.length > 1 ? 's' : '' }}</p>
    </div>

    <div v-if="cartItems.length === 0" class="empty">
      <p class="empty__title">Votre panier est vide</p>
      <p>Ajoutez une reference depuis le catalogue pour ouvrir un ticket.</p>
      <router-link to="/" class="btn btn--quiet empty__action">Retour au catalogue</router-link>
    </div>

    <div v-else class="cart-layout">
      <section class="cart-items card" aria-label="Lignes du panier">
        <div
          v-for="(item, index) in cartItems"
          :key="item.productId ? item.productId._id : index"
          class="cart-item"
        >
          <span class="cart-item__ref">{{ reference(item.productId) }}</span>

          <span class="cart-item__name">{{ item.productId ? item.productId.name : 'Produit inconnu' }}</span>

          <span class="cart-item__amount">
            {{ item.productId ? item.productId.price : 'N/A' }} € x {{ item.quantity }}
          </span>

          <button
            v-if="item.productId"
            @click="handleRemoveItem(item.productId._id)"
            class="remove-item"
            type="button"
            :aria-label="`Retirer ${item.productId.name} du panier`"
          >
            ×
          </button>
        </div>
      </section>

      <aside class="checkout-section card">
        <div class="cart-total">
          <span class="cart-total__label">Total:</span> <span class="cart-total__value">{{ total }}</span> <span class="cart-total__currency">€</span>
        </div>

        <p class="eyebrow">Livraison</p>

        <div class="shipping-address" v-if="showAddressForm">
          <label class="field">
            <span class="field__label">Rue</span>
            <input v-model="shippingAddress.street" placeholder="12 rue du Comptoir" class="address-input field__input" />
          </label>
          <label class="field">
            <span class="field__label">Ville</span>
            <input v-model="shippingAddress.city" placeholder="Paris" class="address-input field__input" />
          </label>
          <label class="field">
            <span class="field__label">Code postal</span>
            <input v-model="shippingAddress.postalCode" placeholder="75002" class="address-input field__input" inputmode="numeric" />
          </label>
        </div>
        <p v-else class="checkout-hint">
          Verifiez vos lignes, puis renseignez l'adresse de livraison.
        </p>

        <button
          v-if="!showAddressForm"
          @click="showAddressForm = true"
          class="checkout-btn btn btn--signal"
          type="button"
        >
          Passer la commande
        </button>
        <button
          v-else
          @click="checkout"
          class="checkout-btn btn btn--signal"
          :disabled="processing || !isAddressValid"
          type="button"
        >
          {{ processing ? 'Traitement…' : 'Confirmer la commande' }}
        </button>

        <div v-if="error" class="error-message notice notice--alert">
          <span class="notice__marker">!</span>
          <span>{{ error }}</span>
        </div>
      </aside>
    </div>
  </div>
</template>

<script>
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import axios from 'axios';

export default {
  name: 'ShoppingCart',
  props: {
    cartItems: {
      type: Array,
      required: true,
      default: () => [],
    },
  },
  emits: ['remove-from-cart', 'cart-cleared'],

  setup(props, { emit }) {
    const router = useRouter();
    const processing = ref(false);
    const error = ref('');
    const showAddressForm = ref(false);
    const shippingAddress = ref({
      street: '',
      city: '',
      postalCode: '',
    });

    const total = computed(() => {
      return props.cartItems.reduce((sum, item) => {
        return sum + (item.productId ? item.productId.price * item.quantity : 0);
      }, 0).toFixed(2).replace(/\B(?=(\d{3})+\.)/g, '\u202f');
    });

    const isAddressValid = computed(() => {
      return (
        shippingAddress.value.street.length > 0 &&
        shippingAddress.value.city.length > 0 &&
        shippingAddress.value.postalCode.length > 0
      );
    });

    // La reference reprend celle affichee sur l'etiquette du catalogue
    const reference = (product) => {
      const id = product && product._id ? String(product._id) : '';
      return id ? id.slice(-6).toUpperCase() : '——————';
    };

    const handleRemoveItem = (productId) => {
      emit('remove-from-cart', productId);
    };

    const checkout = async () => {
      if (!isAddressValid.value) {
        error.value = 'Renseignez la rue, la ville et le code postal pour continuer.';
        return;
      }

      try {
        processing.value = true;
        error.value = '';
        const token = localStorage.getItem('token');

        const orderData = {
          products: props.cartItems
            .filter((item) => item.productId) // S'assurer que productId existe
            .map((item) => ({
              productId: item.productId._id,
              quantity: item.quantity,
            })),
          shippingAddress: shippingAddress.value,
        };

        await axios.post('/api/orders', orderData, {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });

        emit('cart-cleared');
        router.push('/orders');
      } catch (err) {
        console.error('Erreur lors de la commande:', err);
        error.value = 'La commande n\'a pas pu etre creee. Reessayez dans un instant.';
      } finally {
        processing.value = false;
      }
    };

    return {
      total,
      reference,
      checkout,
      processing,
      error,
      showAddressForm,
      shippingAddress,
      isAddressValid,
      handleRemoveItem,
    };
  },
};
</script>

<style scoped>
.empty__action {
  margin-top: 1.5rem;
  text-decoration: none;
}

.cart-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.65fr) minmax(300px, 1fr);
  align-items: start;
  gap: clamp(1.5rem, 3vw, 2.5rem);
}

/* Le ticket : lignes numerotees, chiffres alignes */
.cart-items {
  --card-pad: 0;
  display: flex;
  flex-direction: column;
  padding: 0;
}

.cart-item {
  display: grid;
  grid-template-columns: auto 1fr auto auto;
  align-items: center;
  gap: 1rem;
  padding: 1rem 1.35rem;
  border-bottom: 1px solid var(--rail-deep);
}

.cart-item:last-child { border-bottom: none; }

.cart-item__ref {
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--ink-faint);
}

.cart-item__name {
  font-family: var(--font-display);
  font-weight: 700;
  font-stretch: 106%;
  font-size: var(--t-0);
  letter-spacing: -0.01em;
}

.cart-item__amount {
  font-family: var(--font-mono);
  font-size: var(--t--1);
  color: var(--ink-soft);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.remove-item {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  background: transparent;
  color: var(--ink-soft);
  border: 2px solid var(--rail-deep);
  font-size: 18px;
  line-height: 1;
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease, border-color 0.12s ease;
}

.remove-item:hover {
  background: var(--alert);
  border-color: var(--alert);
  color: #fff;
}

/* Le total reprend la typographie de l'etiquette et coiffe l'action de paiement */
.cart-total {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0 0.25rem;
  margin: calc(var(--card-pad) * -1) calc(var(--card-pad) * -1) 0.35rem;
  padding: 1.1rem var(--card-pad) 1.25rem;
  background: var(--ink);
  color: var(--stock);
}

.cart-total__label {
  width: 100%;
  margin-bottom: 0.4rem;
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--ink-faint);
}

.cart-total__value {
  font-family: var(--font-display);
  font-weight: 900;
  font-stretch: 120%;
  font-size: clamp(2rem, 5vw, 2.75rem);
  line-height: 1;
  letter-spacing: -0.035em;
  color: var(--signal);
  font-variant-numeric: tabular-nums;
}

.cart-total__currency {
  align-self: flex-start;
  margin-left: 0.15rem;
  font-family: var(--font-display);
  font-weight: 900;
  font-stretch: 120%;
  font-size: 1.2rem;
  color: var(--signal);
}

.checkout-section {
  --card-pad: 1.35rem;
  position: sticky;
  top: 6.5rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.checkout-hint {
  font-size: var(--t--1);
  color: var(--ink-soft);
}

.checkout-btn { width: 100%; }

@media (max-width: 860px) {
  .cart-layout { grid-template-columns: minmax(0, 1fr); }
  .checkout-section { position: static; }
}

@media (max-width: 520px) {
  /* La ligne s'empile, le retrait reste a portee de pouce en haut a droite */
  .cart-item {
    grid-template-columns: minmax(0, 1fr) auto;
    row-gap: 0.2rem;
    gap: 0.2rem 1rem;
  }

  .cart-item__ref,
  .cart-item__name,
  .cart-item__amount { grid-column: 1; }

  .remove-item {
    grid-column: 2;
    grid-row: 1 / 4;
    align-self: start;
  }
}
</style>
