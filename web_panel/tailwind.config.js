/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: '#2563EB',
        'primary-light': '#EFF6FF',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif'],
      },
    },
  },
  plugins: [],
}
