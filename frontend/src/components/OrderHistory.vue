<template>
  <div class="orders">
    <div class="page-head">
      <div>
        <p class="eyebrow">Archives</p>
        <h2>Mes commandes</h2>
      </div>
      <p class="meta" v-if="!loading && !error">
        {{ orders.length }} commande{{ orders.length > 1 ? 's' : '' }}
      </p>
    </div>

    <div v-if="loading" class="loading">
      <span class="loading__bar" aria-hidden="true"></span>
      Chargement des commandes…
    </div>

    <div v-else-if="error" class="error notice notice--alert">
      <span class="notice__marker">!</span>
      <span>{{ error }}</span>
    </div>

    <div v-else-if="orders.length === 0" class="no-orders empty">
      <p class="empty__title">Aucune commande</p>
      <p>Vos commandes s'archivent ici des que vous en validez une.</p>
      <router-link to="/" class="btn btn--quiet empty__action">Voir le catalogue</router-link>
    </div>

    <div v-else class="orders-list">
      <article
        v-for="(order, index) in orders"
        :key="order._id"
        class="order-card card"
        :style="{ '--delay': index * 55 + 'ms' }"
      >
        <header class="order-header">
          <span class="order-id">Commande #{{ order._id.slice(-6) }}</span>
          <span :class="['status', order.status]">{{ translateStatus(order.status) }}</span>
        </header>

        <div class="order-body">
          <div class="order-products">
            <p class="eyebrow">Lignes</p>
            <div v-for="product in order.products" :key="product._id" class="product-item">
              <span class="product-name">{{ product.name }}</span>
              <span class="product-details">
                {{ product.price }} € x {{ product.quantity }}
              </span>
            </div>
          </div>

          <div class="order-address">
            <p class="eyebrow">Livraison</p>
            <p>{{ order.shippingAddress.street }}</p>
            <p>{{ order.shippingAddress.city }}, {{ order.shippingAddress.postalCode }}</p>

            <span class="order-total tag">
              <span>{{ euros(order.totalAmount) }}</span><span class="tag__cents">.{{ cents(order.totalAmount) }}</span><span class="tag__currency">€</span>
            </span>
          </div>
        </div>

        <footer class="order-foot">
          <span class="order-date">Commande du {{ formatDate(order.createdAt) }}</span>
        </footer>
      </article>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from 'vue';
import { orderService } from '../services/orderService';

export default {
  name: 'OrderHistory',
  setup() {
    const orders = ref([]);
    const loading = ref(true);
    const error = ref(null);

    const translateStatus = (status) => {
      const translations = {
        'pending': 'En attente',
        'confirmed': 'Confirmée',
        'shipped': 'Expédiée',
        'delivered': 'Livrée',
        'cancelled': 'Annulée'
      };
      return translations[status] || status;
    };

    const parts = (amount) => (Number(amount) || 0).toFixed(2).split('.');
    const euros = (amount) => parts(amount)[0].replace(/\B(?=(\d{3})+(?!\d))/g, '\u202f');
    const cents = (amount) => parts(amount)[1];

    const formatDate = (dateString) => {
      return new Date(dateString).toLocaleDateString('fr-FR', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    };

    const fetchOrders = async () => {
      try {
        loading.value = true;
        orders.value = await orderService.getOrders();
      } catch (err) {
        error.value = 'Les commandes n\'ont pas pu etre chargees. Reessayez dans un instant.';
        console.error('Erreur:', err);
      } finally {
        loading.value = false;
      }
    };

    onMounted(fetchOrders);

    return {
      orders,
      loading,
      error,
      translateStatus,
      formatDate,
      euros,
      cents
    };
  }
};
</script>

<style scoped>
.empty__action {
  margin-top: 1.5rem;
  text-decoration: none;
}

.loading {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1.5rem;
  border: 2px dashed var(--ink-faint);
  font-family: var(--font-mono);
  font-size: var(--t--1);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--ink-soft);
}

.loading__bar {
  width: 48px;
  height: 8px;
  background: var(--rail-deep);
  overflow: hidden;
  position: relative;
}

.loading__bar::after {
  content: '';
  position: absolute;
  inset: 0 auto 0 0;
  width: 40%;
  background: var(--ink);
  animation: scan 1s ease-in-out infinite alternate;
}

@keyframes scan {
  from { transform: translateX(-20%); }
  to { transform: translateX(180%); }
}

.orders-list {
  display: flex;
  flex-direction: column;
  gap: clamp(1.25rem, 2.5vw, 1.75rem);
}

.order-card {
  --card-pad: 0;
  padding: 0;
  animation: rise 0.45s ease both;
  animation-delay: var(--delay, 0ms);
}

.order-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  padding: 1rem 1.35rem;
  background: var(--ink);
  color: var(--stock);
}

.order-id {
  font-family: var(--font-mono);
  font-size: var(--t--1);
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

/* Le statut est tamponne, pas colorie : encre sur carton */
.status {
  padding: 0.3rem 0.7rem;
  border: 2px solid currentColor;
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.status.pending { color: var(--stock); }
.status.confirmed { color: #7bd88f; }
.status.shipped { color: #7fb2ff; }
.status.delivered { background: #7bd88f; border-color: #7bd88f; color: var(--ink); }
.status.cancelled { color: #ff8a7a; }

.order-body {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) minmax(180px, 1fr);
  gap: clamp(1.25rem, 3vw, 2.25rem);
  padding: 1.35rem;
}

.order-products .eyebrow,
.order-address .eyebrow {
  margin-bottom: 0.6rem;
}

.product-item {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--rail-deep);
}

.product-item:last-child { border-bottom: none; }

.product-name {
  font-family: var(--font-display);
  font-weight: 700;
  font-stretch: 106%;
  letter-spacing: -0.01em;
}

.product-details {
  font-family: var(--font-mono);
  font-size: var(--t--1);
  color: var(--ink-soft);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.order-address {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
}

.order-address p {
  color: var(--ink-soft);
  font-size: var(--t--1);
}

.order-total {
  margin-top: auto;
  padding-top: 0.3rem;
  font-size: 1.6rem;
}

.order-foot {
  padding: 0 1.35rem 1.35rem;
}

.order-date {
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--ink-soft);
}

@media (max-width: 640px) {
  .order-body { grid-template-columns: minmax(0, 1fr); }
}
</style>
