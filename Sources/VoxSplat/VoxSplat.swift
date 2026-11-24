/* -----------------------------------------------------------------
 * :: :  A  K  A  R  I  :                                         ::
 * -----------------------------------------------------------------
 * Redistribution  and  use  in  source  and  binary  forms, with or
 * without  modification,  are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions  in  binary  form  must  reproduce  the  above
 *    copyright  notice,  this  list of conditions and the following
 *    disclaimer   in   the  documentation  and/or  other  materials
 *    provided with the distribution.
 *
 * 3. Neither the name of  the copyright holder nor the names of its
 *    contributors  may  be  used  to  endorse  or  promote products
 *    derived  from  this  software  without  specific prior written
 *    permission.
 *
 * THIS   SOFTWARE   IS   PROVIDED  BY  THE  COPYRIGHT  HOLDERS  AND
 * CONTRIBUTORS  "AS  IS"  AND  ANY  EXPRESS  OR IMPLIED WARRANTIES,
 * INCLUDING,   BUT  NOT  LIMITED  TO,  THE  IMPLIED  WARRANTIES  OF
 * MERCHANTABILITY   AND   FITNESS  FOR  A  PARTICULAR  PURPOSE  ARE
 * DISCLAIMED.   IN   NO   EVENT   SHALL  THE  COPYRIGHT  HOLDER  OR
 * CONTRIBUTORS  BE  LIABLE  FOR  ANY  DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL,  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED  TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
 * USE,  DATA,  OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND  ON  ANY  THEORY  OF  LIABILITY,  WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY  WAY  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 *                               Copyright (C) 2026 Wabi Foundation.
 *                                              All rights reserved.
 * -----------------------------------------------------------------
 *  . x x x . o o o . x x x . : : : .    o  x  o    . : : : .
 * ----------------------------------------------------------------- */

import LabGeomVoxSplat
import simd

/// mesh voxelizing and gaussian splat loading from labgeomvoxsplat, in swift types
public enum VoxSplat
{
  /// a voxel the surface passes through, with the solved surface point and its normal
  public struct SurfaceVoxel: Sendable
  {
    public var coord: SIMD3<Int32>
    public var point: SIMD3<Float>
    public var normal: SIMD3<Float>
  }

  /// a gaussian splat with linear rgba color and its covariance upper triangle
  public struct Splat: Sendable
  {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var covariance: (SIMD3<Float>, SIMD3<Float>)
  }

  /// voxelizes a triangle mesh with the qef voxelizer, coords are in whole voxels from the world origin
  public static func voxelize(points: [SIMD3<Float>], triangles: [Int32], voxelSize: Float) -> [SurfaceVoxel]
  {
    guard !points.isEmpty, triangles.count >= 3, voxelSize > 0 else { return [] }

    let lo = points.reduce(points[0]) { simd_min($0, $1) }
    let hi = points.reduce(points[0]) { simd_max($0, $1) }

    // the voxelizer works in a positive grid so the mesh moves to start one voxel past the origin
    let origin = SIMD3<Int32>(floor(lo / voxelSize)) &- 1
    let offset = SIMD3<Float>(origin) * voxelSize
    let flat = points.flatMap { p -> [Float] in
      let q = p - offset
      return [q.x, q.y, q.z]
    }

    let span = SIMD3<Int32>(ceil((hi - lo) / voxelSize)) &+ 3
    var params = ovoxel.ConvertParams()
    params.voxel_size = vector(voxelSize, voxelSize, voxelSize)
    params.grid_min = vector(Int32(0), 0, 0)
    params.grid_max = vector(span.x, span.y, span.z)

    let result = flat.withUnsafeBufferPointer
    { p in
      triangles.withUnsafeBufferPointer
      { t in
        ovoxel.mesh_to_voxels(p.baseAddress, Int32(points.count), t.baseAddress, Int32(triangles.count / 3), params, nil)
      }
    }

    let count = Int(result.coords.size())
    let normals = Int(result.normals.size())
    var voxels: [SurfaceVoxel] = []
    voxels.reserveCapacity(count)

    for i in 0 ..< count
    {
      let c = result.coords[i]
      let d = result.dual_vertices[i]
      let n = i < normals ? result.normals[i] : vector(Float(0), 0, 0)
      voxels.append(SurfaceVoxel(coord: SIMD3(c.x, c.y, c.z) &+ origin,
                                 point: SIMD3(d.x, d.y, d.z) + offset,
                                 normal: SIMD3(n.x, n.y, n.z)))
    }

    return voxels
  }

  /// loads a gaussian splat ply, or a binary splat file by its extension
  public static func loadSplats(path: String) -> [Splat]
  {
    let cloud = path.hasSuffix(".splat") ? ovoxel.load_splat_binary(path) : ovoxel.load_splat_ply(path)
    let count = Int(cloud.splats.size())
    var splats: [Splat] = []
    splats.reserveCapacity(count)

    for i in 0 ..< count
    {
      let s = cloud.splats[i]
      let color = SIMD4(ovoxel.half_to_float(s.color.0), ovoxel.half_to_float(s.color.1),
                        ovoxel.half_to_float(s.color.2), ovoxel.half_to_float(s.color.3))
      let a = SIMD3(ovoxel.half_to_float(s.covA.0), ovoxel.half_to_float(s.covA.1), ovoxel.half_to_float(s.covA.2))
      let b = SIMD3(ovoxel.half_to_float(s.covB.0), ovoxel.half_to_float(s.covB.1), ovoxel.half_to_float(s.covB.2))
      splats.append(Splat(position: SIMD3(s.position.0, s.position.1, s.position.2), color: color, covariance: (a, b)))
    }

    return splats
  }

  /// the covariance upper triangle of a splat turned by a rotation and scaled along its axes
  public static func covariance(rotation: simd_quatf, scale: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>)
  {
    var a: (UInt16, UInt16, UInt16) = (0, 0, 0)
    var b: (UInt16, UInt16, UInt16) = (0, 0, 0)
    let q = rotation.vector

    withUnsafeMutablePointer(to: &a)
    { pa in
      withUnsafeMutablePointer(to: &b)
      { pb in
        pa.withMemoryRebound(to: UInt16.self, capacity: 3)
        { ra in
          pb.withMemoryRebound(to: UInt16.self, capacity: 3)
          { rb in
            ovoxel.compute_covariance(q.w, q.x, q.y, q.z, scale.x, scale.y, scale.z, ra, rb)
          }
        }
      }
    }

    return (SIMD3(ovoxel.half_to_float(a.0), ovoxel.half_to_float(a.1), ovoxel.half_to_float(a.2)),
            SIMD3(ovoxel.half_to_float(b.0), ovoxel.half_to_float(b.1), ovoxel.half_to_float(b.2)))
  }
}

/// builds linalg vectors field by field from their zero init
private func vector(_ x: Float, _ y: Float, _ z: Float) -> ovoxel.float3
{
  var v = ovoxel.float3()
  v.x = x
  v.y = y
  v.z = z
  return v
}

private func vector(_ x: Int32, _ y: Int32, _ z: Int32) -> ovoxel.int3
{
  var v = ovoxel.int3()
  v.x = x
  v.y = y
  v.z = z
  return v
}
