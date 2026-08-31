<template>
  <div class="product-list">
    <div class="page-head">
      <div>
        <p class="eyebrow">Rayon</p>
        <h2>Catalogue</h2>
      </div>
      <p class="meta">{{ products.length }} reference{{ products.length > 1 ? 's' : '' }} en rayon</p>
    </div>

    <div v-if="products.length === 0" class="empty">
      <p class="empty__title">Le rayon est vide</p>
      <p>Aucune reference n'est chargee. Lancez l'initialisation du catalogue pour remplir le rayon.</p>
    </div>

    <div v-else class="products-grid">
      <article
        v-for="(product, index) in products"
        :key="product._id"
        class="product-card card"
        :style="{ '--delay': index * 45 + 'ms' }"
      >
        <header class="product-card__head">
          <h3>{{ product.name }}</h3>
          <p class="description">{{ product.description }}</p>
        </header>

        <p class="price tag tag--hung">
          <span class="tag__euros">{{ euros(product.price) }}</span><span class="tag__cents">.{{ cents(product.price) }}</span><span class="tag__currency">€</span>
        </p>

        <footer class="product-card__foot">
          <div class="product-card__spec">
            <span class="ref">Ref {{ reference(product) }}</span>
            <span v-if="hasStock(product)" class="stock">
              <span class="stock__meter" aria-hidden="true">
                <i v-for="n in 6" :key="n" :class="{ 'is-on': n <= filled(product.stock) }"></i>
              </span>
              {{ product.stock }} en stock
            </span>
          </div>

          <button
            @click="handleAddToCart(product)"
            class="add-to-cart btn"
            :disabled="isAddingToCart"
            type="button"
          >
            {{ isAddingToCart ? 'Ajout…' : 'Ajouter au panier' }}
          </button>
        </footer>
      </article>
    </div>
  </div>
</template>

<script>
import { ref } from 'vue';

export default {
  name: 'ProductList',
  props: {
    products: {
      type: Array,
      required: true
    }
  },
  emits: ['add-to-cart'],
  setup(props, { emit }) {
    const isAddingToCart = ref(false);

    // Le prix se compose comme sur une etiquette : euros en grand, centimes en exposant
    const parts = (price) => (Number(price) || 0).toFixed(2).split('.');
    // Espace fine insecable tous les trois chiffres, comme sur une etiquette
    const euros = (price) => parts(price)[0].replace(/\B(?=(\d{3})+(?!\d))/g, '\u202f');
    const cents = (price) => parts(price)[1];

    // La reference vient de l'identifiant reel du produit
    const reference = (product) => {
      const id = product && product._id ? String(product._id) : '';
      return id ? id.slice(-6).toUpperCase() : '——————';
    };

    const hasStock = (product) => Number.isFinite(Number(product && product.stock));
    const filled = (stock) => Math.max(1, Math.min(6, Math.ceil((Number(stock) || 0) / 5)));

    const handleAddToCart = async (product) => {
      try {
        isAddingToCart.value = true;
        emit('add-to-cart', product);
      } catch (error) {
        console.error('Erreur lors de l\'ajout au panier:', error);
      } finally {
        isAddingToCart.value = false;
      }
    };

    return {
      handleAddToCart,
      isAddingToCart,
      euros,
      cents,
      reference,
      hasStock,
      filled
    };
  }
};
</script>

<style scoped>
.products-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(270px, 1fr));
  gap: clamp(1.5rem, 3vw, 2.25rem);
}

.product-card {
  --card-pad: 1.35rem;
  display: flex;
  flex-direction: column;
  gap: 1.15rem;
  animation: rise 0.45s ease both;
  animation-delay: var(--delay, 0ms);
  transition: transform 0.14s ease, box-shadow 0.14s ease;
}

.product-card:hover {
  transform: translate(-2px, -2px);
  box-shadow: 6px 6px 0 var(--ink);
}

.product-card h3 {
  font-family: var(--font-display);
  font-weight: 700;
  font-stretch: 108%;
  font-size: var(--t-1);
  line-height: 1.12;
  letter-spacing: -0.015em;
}

.description {
  margin-top: 0.4rem;
  color: var(--ink-soft);
  font-size: var(--t--1);
  line-height: 1.5;
}

/* Le drapeau prix deborde du carton, cale a gauche */
.price {
  align-self: flex-start;
  margin-top: auto;
  font-size: 2.6rem;
}

.product-card__foot {
  display: flex;
  flex-direction: column;
  gap: 0.9rem;
}

.product-card__spec {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  padding-top: 0.75rem;
  border-top: 1px solid var(--rail-deep);
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--ink-soft);
}

.stock {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-variant-numeric: tabular-nums;
}

.stock__meter {
  display: inline-flex;
  gap: 2px;
}

.stock__meter i {
  width: 5px;
  height: 11px;
  background: var(--rail-deep);
}

.stock__meter i.is-on { background: var(--ink); }

.add-to-cart { width: 100%; }
</style>
