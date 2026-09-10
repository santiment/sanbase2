import tailwindConfig from 'san-webkit-next/tailwind.config.js'

export default {
  presets: [tailwindConfig],
  content: [
    ...tailwindConfig.content,
    './node_modules/san-webkit-next/dist/**/*.{js,svelte}',
    './src/**/*.{html,js,svelte,ts}',
    './lib/**/*.{js,ts}',
  ],
}
