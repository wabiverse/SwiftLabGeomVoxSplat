import Testing
import VoxSplat
import simd

@Test func voxelizesATriangle()
{
  let points: [SIMD3<Float>] = [SIMD3(-1, -1, 0.05), SIMD3(1, -1, 0.05), SIMD3(0, 1, 0.05)]
  let voxels = VoxSplat.voxelize(points: points, triangles: [0, 1, 2], voxelSize: 0.1)
  #expect(voxels.count > 50)
  #expect(voxels.allSatisfy { abs($0.point.z - 0.05) < 0.11 })
}

@Test func covarianceOfAUnitSplat()
{
  let c = VoxSplat.covariance(rotation: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)), scale: SIMD3(1, 2, 3))
  #expect(abs(c.0.x - 1) < 0.01 && abs(c.1.x - 4) < 0.01 && abs(c.1.z - 9) < 0.05)
}
