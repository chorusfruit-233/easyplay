const lanDefaultPort = 8080;
const lanFallbackPortCount = 10;

List<int> lanDiscoveryPorts(int preferred) => {
  for (
    var port = preferred;
    port <= 65535 && port <= preferred + lanFallbackPortCount;
    port++
  )
    port,
  for (
    var port = lanDefaultPort;
    port <= lanDefaultPort + lanFallbackPortCount;
    port++
  )
    port,
}.toList();
