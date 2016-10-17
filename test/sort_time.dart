main() {
  var list = <DateTime>[
    new DateTime.now().add(const Duration(minutes: 5)),
    new DateTime.now().add(const Duration(minutes: 10)),
    new DateTime.now().add(const Duration(minutes: 15)),
    new DateTime.now().add(const Duration(minutes: 20))
  ];

  list.sort((a, b) {
    return a.compareTo(b);
  });

  print(list);
}