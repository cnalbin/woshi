import XCTest

final class QingJiUITests: XCTestCase {
    func testOnboardingMealFractionAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                                "-serviceURL", "http://localhost:8787"]
        app.launch()
        let service = app.buttons["service.open"]
        XCTAssertTrue(service.waitForExistence(timeout: 10))
        reveal(service, in: app)
        service.tap()
        login("first-user", in: app)
        let start = app.buttons["profile.save"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture("01-个人资料")
        reveal(start, in: app)
        start.tap()
        let manual = app.buttons["meal.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        capture("02-今日首页")
        manual.tap()
        let addFood = app.buttons["food.add"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 5))
        addFood.tap()
        let name = app.textFields["food.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test lunch")
        let kcal = app.textFields["food.kcal"]
        kcal.tap()
        kcal.typeText("250")
        app.buttons["food.done"].tap()
        let half = app.segmentedControls.buttons["1/2"]
        XCTAssertTrue(half.waitForExistence(timeout: 5))
        reveal(half, in: app)
        half.tap()
        capture("03-确认半份饮食")
        let save = app.buttons["meal.save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "125")
        capture("04-保存后首页")
        app.terminate()
        app.launch()
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "125", "Record must survive a real process restart")
        app.tabBars.buttons["我的"].tap()
        capture("05-我的")
        let metabolism = app.buttons["metabolism.open"]
        reveal(metabolism, in: app)
        metabolism.tap()
        let analyze = app.buttons["metabolism.start"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()
        let consent = app.buttons["ai.consent.accept"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        reveal(consent, in: app)
        consent.tap()
        let result = app.staticTexts["UI 集成测试：已通过真实 SSE 接收代谢结果。"]
        let completed = result.waitForExistence(timeout: 30)
        if !completed {
            capture("AI结果接收诊断")
            let debug = XCTAttachment(string: app.debugDescription)
            debug.lifetime = .keepAlways
            self.add(debug)
        }
        XCTAssertTrue(completed, "iOS SSE decoding must work through the real private backend")
        capture("06-AI结果与综合代谢")
        app.navigationBars["代谢分析"].buttons["完成"].tap()
        let backup = app.buttons["backup.open"]
        reveal(backup, in: app)
        backup.tap()
        let enable = app.buttons["backup.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 8))
        enable.tap()
        let confirmEnable = app.alerts.buttons["启用备份"]
        XCTAssertTrue(confirmEnable.waitForExistence(timeout: 8))
        confirmEnable.tap()
        let status = app.staticTexts["backup.status"]
        let success = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "NAS 备份成功"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 20), .completed, "Backup status: \(status.label)")
        app.buttons["backup.restore"].tap()
        let confirmRestore = app.alerts.buttons["恢复"]
        XCTAssertTrue(confirmRestore.waitForExistence(timeout: 8))
        confirmRestore.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已从 NAS 恢复 1 条"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed, "Restore status: \(status.label)")
        capture("07-NAS备份和恢复")
        app.navigationBars.buttons.firstMatch.tap()
        signOut(in: app)
        login("second-user", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 10), "A different account must open a new workspace")
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "0")
        app.tabBars.buttons["我的"].tap()
        signOut(in: app)
        login("first-user", in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "125")
    }

    private func login(_ name: String, in app: XCUIApplication) {
        let address = app.textFields["service.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        if address.value as? String != "http://localhost:8787" {
            address.tap()
            address.typeText("http://localhost:8787")
        }
        let username = app.textFields["service.username"]
        username.tap()
        username.typeText(name)
        let password = app.secureTextFields["service.password"]
        password.tap()
        password.typeText("test-password-only")
        let submit = app.buttons["service.save"]
        reveal(submit, in: app)
        submit.tap()
        let signedIn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: submit)
        XCTAssertEqual(XCTWaiter.wait(for: [signedIn], timeout: 15), .completed, "NAS account login failed")
    }

    private func signOut(in app: XCUIApplication) {
        let service = app.buttons["service.open"]
        reveal(service, in: app)
        service.tap()
        let logout = app.buttons["service.logout"]
        XCTAssertTrue(logout.waitForExistence(timeout: 8))
        logout.tap()
        let confirm = app.alerts.buttons["退出登录"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        if !element.isHittable {
            capture("未能找到目标控件")
            let debug = XCTAttachment(string: app.debugDescription)
            debug.lifetime = .keepAlways
            self.add(debug)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
