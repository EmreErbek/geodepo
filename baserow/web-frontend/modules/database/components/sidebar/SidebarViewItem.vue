<template>
  <li class="tree__sub tree__sub--view" :class="{ active: isSelected }">
    <a
      class="tree__sub-link tree__sub-link--view"
      :title="view.name"
      :href="resolveViewHref()"
      @mousedown.prevent
      @click.prevent="selectView"
    >
      <i
        class="tree__sub-view-icon"
        :class="`${view._.type.colorClass} ${view._.type.iconClass}`"
      ></i>
      <span class="tree__sub-view-name">{{ view.name }}</span>
    </a>
  </li>
</template>

<script>
import { pageFinished } from '@baserow/modules/core/utils/routing'
import { nextTick, useNuxtApp } from '#imports'

export default {
  name: 'SidebarViewItem',
  props: {
    database: {
      type: Object,
      required: true,
    },
    table: {
      type: Object,
      required: true,
    },
    view: {
      type: Object,
      required: true,
    },
  },
  setup() {
    const nuxtApp = useNuxtApp()
    return { nuxtApp }
  },
  computed: {
    isSelected() {
      if (this.view._?.selected) {
        return true
      }

      const route = this.$router.currentRoute.value
      return (
        route.name === 'database-table' &&
        parseInt(route.params.databaseId) === this.database.id &&
        parseInt(route.params.tableId) === this.table.id &&
        parseInt(route.params.viewId) === this.view.id
      )
    },
  },
  methods: {
    setLoading(database, value) {
      this.$store.dispatch('application/setItemLoading', {
        application: database,
        value,
      })
    },
    async selectView() {
      if (this.isSelected) {
        return
      }

      this.setLoading(this.database, true)

      try {
        const failure = await this.$router.push({
          name: 'database-table',
          params: {
            databaseId: this.database.id,
            tableId: this.table.id,
            viewId: this.view.id,
          },
        })
        if (failure === undefined) {
          await pageFinished(this.nuxtApp)
          await nextTick()
        }
      } finally {
        this.setLoading(this.database, false)
      }
    },
    resolveViewHref() {
      return this.$router.resolve({
        name: 'database-table',
        params: {
          databaseId: this.database.id,
          tableId: this.table.id,
          viewId: this.view.id,
        },
      }).href
    },
  },
}
</script>