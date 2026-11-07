import XCTest

final class QingJiUITests: XCTestCase {
    func testOnboardingMealFractionAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let start = app.buttons["profile.save"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture("01-个人资料")
        reveal(start, in: app)
        start.tap()
        let manual = app.buttons["meal.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        capture("02-今日首页")
        manual.tap()
        let add = app.buttons["food.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
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
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
