# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Quokka],
  quokka: [exclude: [:inefficient_functions]],
  line_length: 120
]
