import Metal
import Foundation

extension MTLDevice {
    /// Loads the default Metal library in a way that works when MetalX is a SwiftPM package.
    /// Tries `makeDefaultLibrary(bundle: .module)` first, then falls back to locating any
    /// `.metallib` inside the package bundle and creating a library from its URL.
    func mxMakeDefaultLibrary() -> MTLLibrary? {
        #if SWIFT_PACKAGE
        // 1) Ask Metal to load the default library from the package bundle
        if let lib = try? makeDefaultLibrary(bundle: .module) {
            return lib
        }

        // 2) Manually search for a compiled metallib inside the package bundle
        //    Xcode typically emits `default.metallib` at the bundle root, but we search broadly.
        let bundle = Bundle.module
        let fm = FileManager.default
        if let bundleURL = bundle.resourceURL {
            if let libURL = try? fm
                .subpathsOfDirectory(atPath: bundleURL.path)
                .compactMap({ sub -> URL? in
                    let url = bundleURL.appendingPathComponent(sub)
                    return url.pathExtension == "metallib" ? url : nil
                })
                .first {
                if let library = try? makeLibrary(URL: libURL) { return library }
            }
            // Also try common default name directly
            if let defaultURL = bundle.url(forResource: "default", withExtension: "metallib"),
               let library = try? makeLibrary(URL: defaultURL) {
                return library
            }
        }
        #endif

        // 3) Fallback to main bundle default
        return makeDefaultLibrary()
    }
}
