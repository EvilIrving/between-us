import XCTest
import UIKit
import SpriteKit
@testable import BetweenUsPhysicsDemo

// 这些测试需要苹果模拟器，生成环境没有运行；用于验证真实框架装配与遮挡独立性。
@MainActor
final class ApplePhysicsTests: XCTestCase {
    private func installed(_ recipe:VesselRecipe) -> (SKView,VesselPhysicsScene) {
        let view=SKView(frame:CGRect(x:0,y:0,width:390,height:700))
        view.isPaused=true
        let scene=VesselPhysicsScene(recipe:recipe,initialCount:1)
        view.presentScene(scene)
        scene.didMove(to:view) // 资源装载幂等，未进入窗口的测试视图也可明确初始化。
        scene.update(1)
        return (view,scene)
    }
    func testAllAssetsAndBodiesInstall() {
        for recipe in ResourceCatalog.all {
            let (view,scene)=installed(recipe)
            defer { view.presentScene(nil) }
            XCTAssertEqual(scene.makeSnapshot().active.count,1,recipe.id)
            XCTAssertNotNil(scene.childNode(withName:"physics.innerWall")?.physicsBody)
            let bodies=scene.children.compactMap(\.physicsBody).filter { $0.categoryBitMask == PhysicsFactory.entityCategory }
            XCTAssertEqual(bodies.count,1)
            for body in bodies {
                XCTAssertTrue(body.isDynamic)
                XCTAssertTrue(body.affectedByGravity)
                XCTAssertEqual(body.mass,recipe.entity.material.mass,accuracy:0.0001)
                XCTAssertEqual(body.friction,recipe.entity.material.friction,accuracy:0.0001)
                XCTAssertEqual(body.collisionBitMask,PhysicsFactory.wallCategory|PhysicsFactory.entityCategory)
            }
        }
    }
    func testXRayDoesNotReplaceOrFreezePhysics() {
        for recipe in ResourceCatalog.all {
            let (view,scene)=installed(recipe)
            defer { view.presentScene(nil) }
            let before=scene.makeSnapshot()
            let bodyIDs=scene.children.compactMap(\.physicsBody).map(ObjectIdentifier.init)
            scene.setInspection(showGeometry:true,xRay:true)
            XCTAssertEqual(scene.makeSnapshot(),before)
            XCTAssertEqual(scene.children.compactMap(\.physicsBody).map(ObjectIdentifier.init),bodyIDs)
            scene.setInspection(showGeometry:false,xRay:false)
            XCTAssertEqual(scene.makeSnapshot(),before)
            XCTAssertEqual(scene.children.compactMap(\.physicsBody).map(ObjectIdentifier.init),bodyIDs)
        }
    }
    func testOpaqueRecipesKeepPlacedBodies() throws {
        for recipe in [ResourceCatalog.capsuleBox,ResourceCatalog.paperBin] {
            let (view,scene)=installed(recipe)
            defer { view.presentScene(nil) }
            var snapshot=scene.makeSnapshot()
            XCTAssertEqual(snapshot.active.count,1)
            guard !snapshot.active.isEmpty else { continue }
            // 移到桶/盒的隐藏内腔，不做物理推进，只验证遮挡不会删除实体。
            snapshot.active[0].position=recipe.container.mapping.scenePoint(CGPoint(x:350,y:550))
            try scene.restore(snapshot)
            scene.didSimulatePhysics()
            XCTAssertEqual(scene.makeSnapshot().active.count,1)
            XCTAssertEqual(scene.makeSnapshot().active.first?.position,snapshot.active.first?.position)
        }
    }
    func testSnapshotRoundTripOnRealNodes() throws {
        let (view,scene)=installed(ResourceCatalog.starJar)
        defer { view.presentScene(nil) }
        let before=scene.makeSnapshot()
        scene.resetDemo()
        try scene.restore(before)
        let after=scene.makeSnapshot()
        XCTAssertEqual(before.active.map(\.request),after.active.map(\.request))
        XCTAssertEqual(before.active.map(\.position),after.active.map(\.position))
        XCTAssertEqual(before.active.map(\.rotation),after.active.map(\.rotation))
    }
    func testDetachTransfersOwnershipAndKeepsID() {
        let (view,scene)=installed(ResourceCatalog.starJar)
        defer { view.presentScene(nil) }
        guard let id=scene.makeSnapshot().active.first?.request.id else { return XCTFail("未生成实体") }
        let node=scene.detachForPresentation(id:id)
        XCTAssertEqual(node?.name,id.uuidString)
        XCTAssertNil(node?.physicsBody)
        XCTAssertNil(node?.parent)
        XCTAssertTrue(scene.makeSnapshot().active.isEmpty)
        XCTAssertTrue(scene.queueToken(id:id))
    }
}
