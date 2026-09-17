import XCTest
@testable import PhysicsCore

final class PhysicsCoreTests: XCTestCase {
    func testAllRecipesValidate() {
        XCTAssertEqual(ResourceCatalog.all.count,3)
        for recipe in ResourceCatalog.all { XCTAssertEqual(GeometryMath.validate(recipe),[],recipe.id) }
    }
    func testCatalogRoundTrip() throws {
        let data = try JSONEncoder().encode(ResourceCatalog.all)
        XCTAssertEqual(try JSONDecoder().decode([VesselRecipe].self,from:data),ResourceCatalog.all)
    }
    func testCoordinateRoundTrip() {
        for recipe in ResourceCatalog.all {
            for pixel in recipe.container.innerWall {
                let m = recipe.container.mapping
                let returned = m.pixelPoint(m.scenePoint(pixel))
                XCTAssertEqual(pixel.x,returned.x,accuracy:0.00001)
                XCTAssertEqual(pixel.y,returned.y,accuracy:0.00001)
            }
        }
    }
    func testWallsAreOpenAndExtendToRealInteriorBottom() {
        for recipe in ResourceCatalog.all {
            let wall = recipe.container.innerWall
            XCTAssertNotEqual(wall.first,wall.last)
            XCTAssertGreaterThan(wall.count,12)
            XCTAssertGreaterThan(wall.map(\.y).max()!,600,recipe.id)
            XCTAssertGreaterThan(GeometryMath.signedArea(wall).magnitude,50_000,recipe.id)
        }
    }
    func testWallChainDoesNotSelfIntersect() {
        for recipe in ResourceCatalog.all {
            let points = recipe.container.innerWall
            for i in 0..<(points.count-2) {
                for j in (i+2)..<(points.count-1) {
                    let a=points[i],b=points[i+1],c=points[j],d=points[j+1]
                    let cross1=GeometryMath.cross(a,b,c), cross2=GeometryMath.cross(a,b,d)
                    let cross3=GeometryMath.cross(c,d,a), cross4=GeometryMath.cross(c,d,b)
                    XCTAssertFalse(cross1*cross2 < 0 && cross3*cross4 < 0,"\(recipe.id): \(i),\(j)")
                }
            }
        }
    }
    func testAllConvexPiecesWithinVertexLimit() {
        for recipe in ResourceCatalog.all {
            for points in GeometryMath.expandedPolygons(recipe.entity.geometry) {
                XCTAssertTrue(GeometryMath.isConvex(points),recipe.id)
                XCTAssertLessThanOrEqual(points.count,8)
                let local=GeometryMath.counterclockwise(points.map(recipe.entity.geometry.localPoint))
                XCTAssertGreaterThan(GeometryMath.signedArea(local),0)
            }
        }
    }
    func testCapsuleHasThreeNonoverlappingConvexPieces() {
        let g=ResourceCatalog.capsuleBox.entity.geometry
        let pieces=GeometryMath.expandedPolygons(g)
        XCTAssertEqual(pieces.count,3)
        XCTAssertEqual(pieces.map(\.count),[4,7,7])
        let totalArea=pieces.reduce(CGFloat.zero) { $0+abs(GeometryMath.signedArea($1)) }
        let rect=CGRect(x:218,y:114,width:86,height:274)
        let trueArea=rect.width*(rect.height-rect.width)+CGFloat.pi*pow(rect.width/2,2)
        XCTAssertGreaterThan(totalArea/trueArea,0.97)
        XCTAssertLessThanOrEqual(totalArea,trueArea)
    }
    func testTokenAnchorMapsReferenceCenterToOrigin() {
        for recipe in ResourceCatalog.all {
            let g=recipe.entity.geometry
            XCTAssertEqual(g.localPoint(CGPoint(x:g.referenceFrame.midX,y:g.referenceFrame.midY)),.zero)
        }
    }
    func testOriginalStarGeometryAndMaterialUnchanged() {
        let r=ResourceCatalog.starJar
        XCTAssertEqual(r.container.mapping.sceneSize,CGSize(width:500,height:724))
        XCTAssertEqual(r.container.mapping.origin,CGPoint(x:-112,y:0))
        XCTAssertEqual(r.container.innerWall.count,31)
        XCTAssertEqual(GeometryMath.expandedPolygons(r.entity.geometry).count,6)
        XCTAssertEqual(r.entity.geometry.displaySize,CGSize(width:108,height:108))
        XCTAssertEqual(r.entity.material.mass,0.03)
        XCTAssertEqual(r.entity.material.friction,0.55)
        XCTAssertEqual(r.entity.material.restitution,0.12)
        XCTAssertEqual(r.entity.material.linearDamping,0.22)
        XCTAssertEqual(r.entity.material.angularDamping,0.35)
        XCTAssertEqual(r.policy.gravity,CGPoint(x:0,y:-2.4))
        XCTAssertEqual(r.policy.spawn.center,CGPoint(x:250,y:662))
        XCTAssertEqual(r.policy.spawn.interval,0.65)
        XCTAssertEqual(r.policy.drag.maximumStretch,36)
        XCTAssertEqual(r.policy.drag.maximumHandleSpeed,480)
        XCTAssertEqual(r.policy.maximumLinearSpeed,550)
        XCTAssertEqual(r.policy.maximumAngularSpeed,7)
    }
    func testQueueDeduplicatesBothStates() {
        var q=TokenQueue(capacity:10)
        let r=TokenRequest(id:UUID(),skinID:"skin")
        XCTAssertTrue(q.enqueue(r)); XCTAssertFalse(q.enqueue(r))
        XCTAssertEqual(q.activateNext(),r); XCTAssertFalse(q.enqueue(r))
        XCTAssertEqual(q.totalCount,1)
    }
    func testQueueCapacityIncludesWaiting() {
        var q=TokenQueue(capacity:2)
        XCTAssertTrue(q.enqueue(TokenRequest(id:UUID(),skinID:"a")))
        XCTAssertTrue(q.enqueue(TokenRequest(id:UUID(),skinID:"a")))
        _=q.activateNext()
        XCTAssertFalse(q.enqueue(TokenRequest(id:UUID(),skinID:"a")))
        XCTAssertEqual(q.totalCount,2)
    }
    func testRecoveryRetainsIdentityAndCapacity() {
        var q=TokenQueue(capacity:1)
        let request=TokenRequest(id:UUID(),skinID:"a")
        _=q.enqueue(request); _=q.activateNext()
        XCTAssertTrue(q.recover(request.id))
        XCTAssertEqual(q.waiting,[request]); XCTAssertEqual(q.totalCount,1)
        XCTAssertFalse(q.recover(request.id))
    }
    func testDetachFreesOnlyRequestedIdentity() {
        var q=TokenQueue(capacity:2)
        let a=TokenRequest(id:UUID(),skinID:"a"),b=TokenRequest(id:UUID(),skinID:"b")
        _=q.enqueue(a);_=q.enqueue(b);_=q.activateNext()
        XCTAssertEqual(q.remove(a.id),a)
        XCTAssertEqual(q.waiting,[b]);XCTAssertEqual(q.totalCount,1)
        XCTAssertNil(q.remove(a.id))
    }
    func testClearResetsBothStates() {
        var q=TokenQueue(capacity:2)
        _=q.enqueue(TokenRequest(id:UUID(),skinID:"a"));_=q.activateNext()
        _=q.enqueue(TokenRequest(id:UUID(),skinID:"a"));q.clear()
        XCTAssertEqual(q.totalCount,0);XCTAssertNil(q.activateNext())
    }
    private func snapshot(_ recipe:VesselRecipe = ResourceCatalog.starJar) -> VesselSnapshot {
        let r=TokenRequest(id:UUID(),skinID:recipe.defaultSkin.id)
        return VesselSnapshot(recipeID:recipe.id,geometryVersion:recipe.geometryVersion,
            active:[TokenPlacement(request:r,position:recipe.policy.spawn.center,rotation:0.4,
                                   velocity:CGPoint(x:1,y:2),angularVelocity:0.3,isResting:false)],waiting:[])
    }
    func testSnapshotJSONRoundTrip() throws {
        let s=snapshot()
        let data=try JSONEncoder().encode(s)
        XCTAssertEqual(s,try JSONDecoder().decode(VesselSnapshot.self,from:data))
        XCTAssertEqual(s.validationErrors(for:ResourceCatalog.starJar),[])
    }
    func testSnapshotRejectsOtherRecipe() {
        XCTAssertFalse(snapshot().validationErrors(for:ResourceCatalog.paperBin).isEmpty)
    }
    func testSnapshotRejectsDifferentGeometryVersion() {
        var s=snapshot();s.geometryVersion += 1
        XCTAssertFalse(s.validationErrors(for:ResourceCatalog.starJar).isEmpty)
    }
    func testSnapshotRejectsDuplicateIDs() {
        var s=snapshot();s.waiting=[s.active[0].request]
        XCTAssertFalse(s.validationErrors(for:ResourceCatalog.starJar).isEmpty)
    }
    func testSnapshotRejectsUnknownSkin() {
        var s=snapshot();s.active[0].request.skinID="unknown"
        XCTAssertFalse(s.validationErrors(for:ResourceCatalog.starJar).isEmpty)
    }
    func testSnapshotRejectsNonfiniteMotion() {
        var s=snapshot();s.active[0].velocity.x = .nan
        XCTAssertFalse(s.validationErrors(for:ResourceCatalog.starJar).isEmpty)
    }
    func testSnapshotRejectsOutOfScenePlacement() {
        var s=snapshot();s.active[0].position.x = -10000
        XCTAssertFalse(s.validationErrors(for:ResourceCatalog.starJar).isEmpty)
    }
    func testStarSkinsCanShareOneGeometry() {
        var recipe=ResourceCatalog.starJar
        let geometry=recipe.entity.geometry
        var skin=recipe.defaultSkin;skin.id="another-star";skin.asset="another-artwork"
        recipe.skins.append(skin)
        XCTAssertEqual(GeometryMath.validate(recipe),[])
        XCTAssertEqual(recipe.entity.geometry,geometry)
    }
    func testTransparentArtworkDoesNotChangeCollisionConfiguration() {
        var recipe=ResourceCatalog.paperBin
        let before=recipe.container.innerWall,geometry=recipe.entity.geometry,policy=recipe.policy
        for i in recipe.container.layers.indices {
            recipe.container.layers[i].asset="future-transparent-artwork"
            recipe.container.layers[i].opacity=0.2
        }
        XCTAssertEqual(recipe.container.innerWall,before)
        XCTAssertEqual(recipe.entity.geometry,geometry)
        XCTAssertEqual(recipe.policy,policy)
        XCTAssertEqual(GeometryMath.validate(recipe),[])
    }
    func testDifferentEntitySkinRejected() {
        var recipe=ResourceCatalog.starJar
        recipe.skins.append(ResourceCatalog.capsuleBox.defaultSkin)
        XCTAssertFalse(GeometryMath.validate(recipe).isEmpty)
    }
    func testNonuniformScaleRejected() {
        var recipe=ResourceCatalog.paperBin
        recipe.entity.geometry.displaySize.height *= 2
        XCTAssertFalse(GeometryMath.validate(recipe).isEmpty)
    }
}
