import SwiftUI
import WebKit

/// Map preview of the selected table's geometry. Samples a bounded set of features, reprojects
/// EPSG:27700 (BNG) → 4326 when the coordinates look projected (leaving lon/lat as-is), and
/// renders them on a MapLibre GL basemap.
struct MapPane: View {
    @Environment(AppModel.self) private var model

    @State private var geojson: String?
    @State private var featureCount = 0
    @State private var loading = false
    @State private var error: String?

    private var geometryColumn: CatalogNode? {
        model.selectedNode?.children?.first { $0.isGeometry }
    }

    var body: some View {
        Group {
            if let node = model.selectedNode, node.kind == .table || node.kind == .view,
               let geometry = geometryColumn {
                ZStack(alignment: .topLeading) {
                    GeoMapView(geojson: geojson)
                    banner(node: node, geometry: geometry)
                }
                .task(id: "\(node.id)#\(model.activeSnapshot?.id ?? -1)") {
                    await load(table: node.name, column: geometry.name)
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.base)
    }

    private func banner(node: CatalogNode, geometry: CatalogNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.scope").foregroundStyle(Palette.geometry)
            Text(verbatim: "\(node.name).\(geometry.name)").font(.stratumMono(11, .medium))
                .foregroundStyle(Palette.textPrimary)
            if loading { ProgressView().controlSize(.small) }
            else if let error { Text(error).font(.stratumMono(9)).foregroundStyle(Palette.danger).lineLimit(1) }
            else { Text("\(featureCount) features").font(.stratumMono(9)).foregroundStyle(Palette.textSecondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.surface.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(Palette.hairline))
        .padding(12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "map").font(.system(size: 30)).foregroundStyle(Palette.textTertiary)
            Text("This table has no geometry column")
                .font(.stratumUI(13)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(table: String, column: String) async {
        loading = true; error = nil; geojson = nil
        defer { loading = false }
        do {
            // Reproject only when the geometry looks projected (BNG easting/northing).
            let result = try await model.query("""
                SELECT ST_AsGeoJSON(
                    CASE WHEN abs(ST_X(ST_Centroid("\(column)"))) > 180
                         THEN ST_Transform(ST_Simplify("\(column)", 20), 'EPSG:27700', 'EPSG:4326', always_xy := true)
                         ELSE "\(column)" END) AS g
                FROM "\(table)" WHERE "\(column)" IS NOT NULL
                LIMIT 800;
                """)
            let geometries = result.rows.compactMap { $0.first?.stringValue }.filter { !$0.isEmpty }
            featureCount = geometries.count
            let features = geometries
                .map { "{\"type\":\"Feature\",\"properties\":{},\"geometry\":\($0)}" }
                .joined(separator: ",")
            geojson = "{\"type\":\"FeatureCollection\",\"features\":[\(features)]}"
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// A MapLibre GL basemap (MapTiler tiles) in a WKWebView, fed a GeoJSON FeatureCollection.
struct GeoMapView: NSViewRepresentable {
    let geojson: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://tiles.local/"))
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.inject(geojson)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var lastInjected: String?
        private var pending: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            inject(pending)
        }

        func inject(_ geojson: String?) {
            guard let geojson, geojson != lastInjected else { return }
            pending = geojson
            guard loaded, let webView else { return }
            lastInjected = geojson
            webView.evaluateJavaScript("window.setData(\(geojson));")
        }
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
    <link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet">
    <style>html,body,#map{margin:0;height:100%;width:100%;background:#eceae4}</style>
    </head><body><div id="map"></div><script>
    const TEAL = '#1E7A72';
    const map = new maplibregl.Map({
      container: 'map',
      style: 'https://api.maptiler.com/maps/dataviz/style.json?key=REDACTED_MAPTILER_KEY',
      center: [-2.2, 54.2], zoom: 4.4, attributionControl: false
    });
    map.addControl(new maplibregl.NavigationControl({showCompass:false}), 'top-right');
    function addLayers() {
      map.addSource('geo', { type:'geojson', data:{type:'FeatureCollection',features:[]} });
      map.addLayer({id:'geo-fill', type:'fill', source:'geo',
        filter:['==','$type','Polygon'], paint:{'fill-color':TEAL,'fill-opacity':0.22}});
      map.addLayer({id:'geo-line', type:'line', source:'geo',
        filter:['==','$type','Polygon'], paint:{'line-color':TEAL,'line-width':1.1}});
      map.addLayer({id:'geo-pt', type:'circle', source:'geo',
        filter:['==','$type','Point'], paint:{'circle-color':TEAL,'circle-radius':4,
        'circle-stroke-color':'#ffffff','circle-stroke-width':1}});
    }
    map.on('load', addLayers);
    window.setData = function(fc) {
      const apply = () => {
        const src = map.getSource('geo');
        if (!src) { return; }
        src.setData(fc);
        try {
          const b = new maplibregl.LngLatBounds();
          const walk = (c) => { if (typeof c[0] === 'number') b.extend(c); else c.forEach(walk); };
          (fc.features||[]).forEach(f => f.geometry && f.geometry.coordinates && walk(f.geometry.coordinates));
          if (!b.isEmpty()) map.fitBounds(b, {padding:36, maxZoom:13, duration:400});
        } catch(e) {}
      };
      if (map.getSource('geo')) apply(); else map.on('load', apply);
    };
    </script></body></html>
    """
}
