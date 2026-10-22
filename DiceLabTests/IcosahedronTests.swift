import simd
import Testing
@testable import DiceLab

/// The d20's raw geometry data — both engines' meshes and colliders build
/// on `Icosahedron`, so a typo in the table must fail here, not render as
/// a crooked die.
struct IcosahedronTests {
    @Test("12 vertices, all on the unit circumsphere")
    func verticesOnUnitSphere() {
        #expect(Icosahedron.vertices.count == 12)
        #expect(Icosahedron.vertices.allSatisfy {
            abs(simd_length($0) - 1) < 1e-5
        })
    }

    @Test("20 faces, every one an equilateral triangle")
    func regularFaces() {
        #expect(Icosahedron.faces.count == 20)
        for face in Icosahedron.faces {
            let v0 = Icosahedron.vertices[face.x]
            let v1 = Icosahedron.vertices[face.y]
            let v2 = Icosahedron.vertices[face.z]
            let edges = [simd_distance(v0, v1), simd_distance(v1, v2),
                         simd_distance(v2, v0)]
            #expect(abs(edges[1] - edges[0]) < 1e-5)
            #expect(abs(edges[2] - edges[0]) < 1e-5)
        }
    }

    /// A normal must be unit, point outward (aligned with the face
    /// centroid), and agree with the winding — the stored triples are
    /// counter-clockwise seen from outside, which is what produces the
    /// outward cross product in the first place.
    @Test("normals are unit, outward, and consistent with the winding")
    func normalsOutward() {
        for (i, face) in Icosahedron.faces.enumerated() {
            let v0 = Icosahedron.vertices[face.x]
            let v1 = Icosahedron.vertices[face.y]
            let v2 = Icosahedron.vertices[face.z]
            let normal = Icosahedron.normals[i]
            #expect(abs(simd_length(normal) - 1) < 1e-5)
            let centroid = (v0 + v1 + v2) / 3
            #expect(simd_dot(normal, centroid) > 0)
            let wound = simd_normalize(simd_cross(v1 - v0, v2 - v0))
            #expect(simd_dot(normal, wound) > 1 - 1e-5)
        }
    }

    /// The value table's sum-to-21 convention reads faces as antipodal
    /// pairs — this ordering is the contract that makes it work.
    @Test("faces come in antipodal pairs: 2k opposes 2k + 1")
    func antipodalPairs() {
        for k in 0..<10 {
            #expect(simd_distance(Icosahedron.normals[2 * k],
                                  -Icosahedron.normals[2 * k + 1]) < 1e-5)
        }
    }

    /// The icosahedron's face normals are the dual dodecahedron's vertex
    /// directions: (±1, ±1, ±1)/√3 plus cyclic permutations of
    /// (0, ±φ, ±1/φ) — a check that the geometry really is regular, not
    /// just self-consistent.
    @Test("the normals are the dual dodecahedron's vertex directions")
    func dodecahedronDirections() {
        let phi = (1 + Float(5).squareRoot()) / 2
        var expected: [SIMD3<Float>] = []
        let signs: [Float] = [-1, 1]
        for x in signs { for y in signs { for z in signs {
            expected.append(simd_normalize(SIMD3(x, y, z)))
        }}}
        for s1 in signs { for s2 in signs {
            expected.append(simd_normalize(SIMD3(0, s1 * phi, s2 / phi)))
            expected.append(simd_normalize(SIMD3(s1 * phi, s2 / phi, 0)))
            expected.append(simd_normalize(SIMD3(s1 / phi, 0, s2 * phi)))
        }}
        #expect(expected.count == 20)
        for normal in Icosahedron.normals {
            #expect(expected.contains { simd_distance($0, normal) < 1e-5 })
        }
    }

    /// Gaming-die balance: the five faces meeting at every vertex must
    /// not pool the highs or lows in one neighbourhood. 5 × 10.5 is the
    /// unreachable ideal, so the convention settles for 52 or 53 —
    /// computed from `faces`, not a hardcoded adjacency.
    @Test("every vertex's five d20 faces sum to 52 or 53")
    func vertexSumsBalance() {
        let values = DieFace.axes(for: .d20).map(\.value)
        var sums = [Int: Int]()
        for (i, face) in Icosahedron.faces.enumerated() {
            for vertex in [face.x, face.y, face.z] {
                sums[vertex, default: 0] += values[i]
            }
        }
        #expect(sums.count == 12)
        #expect(sums.values.allSatisfy { $0 == 52 || $0 == 53 })
    }

    /// The other half of the convention: faces sharing an edge (two
    /// vertices) never carry consecutive values — a spindown's run of
    /// neighbours is exactly what this rules out.
    @Test("no edge-adjacent d20 faces carry consecutive values")
    func noConsecutiveNeighbours() {
        let values = DieFace.axes(for: .d20).map(\.value)
        for (i, face) in Icosahedron.faces.enumerated() {
            let mine: Set = [face.x, face.y, face.z]
            for (j, other) in Icosahedron.faces.enumerated() where j > i {
                guard mine.intersection([other.x, other.y, other.z]).count == 2
                else { continue }
                #expect(abs(values[i] - values[j]) != 1)
            }
        }
    }
}
