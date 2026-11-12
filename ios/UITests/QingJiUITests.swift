import XCTest

final class QingJiUITests: XCTestCase {
    func testOnboardingMealFractionAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                                "-serviceURL", "http://localhost:8787", "-uiTestPhoto"]
        app.launch()
        XCTAssertTrue(app.staticTexts["app.build"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["app.build"].label, "版本 0.10.0 · 构建 12")
        capture("00-注册与版本信息")
        login("registered-user", registering: true, in: app)
        let profile = app.buttons["profile.open"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let start = app.buttons["profile.save"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        capture("01-个人资料")
        reveal(start, in: app)
        start.tap()
        let manual = app.buttons["meal.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        verifyActionPair(app.buttons["meal.photo"], manual)
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
        app.terminate()
        app.launchArguments += ["-qingji.appearanceMode", "dark"]
        app.launch()
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        verifyActionPair(app.buttons["meal.photo"], manual)
        capture("04b-今日深色")
        app.terminate()
        app.launchArguments.removeLast(2)
        app.launch()
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["app.build"].waitForExistence(timeout: 5))
        capture("05-我的")
        verifyFreeMembership(in: app)
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
        app.tabBars.buttons["趋势"].tap()
        let month = app.segmentedControls.buttons["月"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        capture("07-月趋势")
        app.segmentedControls.buttons["年"].tap()
        capture("08-年趋势")
        app.tabBars.buttons["我的"].tap()
        let backup = app.buttons["backup.open"]
        if !backup.isHittable { app.swipeDown() }
        reveal(backup, in: app)
        backup.tap()
        let status = app.staticTexts["sync.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let success = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "已同步"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [success], timeout: 30), .completed)
        capture("10-自动同步")
        app.navigationBars.buttons.firstMatch.tap()
        signOut(in: app)
        login("second-user", in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 10), "New accounts should enter the home screen")
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "0")
        app.tabBars.buttons["我的"].tap()
        signOut(in: app)
        login("registered-user", in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["intake.total"].label, "125")
        verifyPhotoCancellationAndReview(in: app)
        app.tabBars.buttons["我的"].tap()
        signOut(in: app)
        login("first-user", in: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", ["1500", "1,500"]), object: app.staticTexts["intake.total"])
        let loaded = XCTWaiter.wait(for: [restored], timeout: 30)
        if loaded != .completed {
            capture("历史账号同步诊断")
            let details = XCTAttachment(string: app.debugDescription)
            details.lifetime = .keepAlways
            self.add(details)
        }
        XCTAssertEqual(loaded, .completed)
        verifyRepeatedNavigation(in: app)
        verifyMemberScreens(in: app)
    }

    private func verifyFreeMembership(in app: XCUIApplication) {
        let entry = app.buttons["membership.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["轻记会员"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["今日"].exists, "Membership subpages should match the standalone design")
        capture("15-开通会员")
        app.navigationBars.buttons.firstMatch.tap()
        let builtin = app.buttons["model.builtin"]
        reveal(builtin, in: app)
        builtin.tap()
        XCTAssertTrue(app.staticTexts["免费体验剩余"].waitForExistence(timeout: 8))
        capture("16-内置 DeepSeek")
        app.navigationBars.buttons.firstMatch.tap()
        let custom = app.buttons["model.open"]
        reveal(custom, in: app)
        custom.tap()
        XCTAssertTrue(app.buttons["开通会员使用"].waitForExistence(timeout: 5))
        capture("17-免费账号自定义模型入口")
        app.navigationBars.buttons.firstMatch.tap()
        let appearance = app.buttons["appearance.open"]
        reveal(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.buttons["skin.orange"].waitForExistence(timeout: 5))
        capture("18-外观")
        reveal(app.buttons["skin.orange"], in: app)
        app.buttons["skin.orange"].tap()
        XCTAssertTrue(app.buttons["开通会员使用"].waitForExistence(timeout: 5))
        capture("19-奶油暖橙预览")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
    }

    private func verifyMemberScreens(in app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["membership.entry"]
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.staticTexts["会员有效"].waitForExistence(timeout: 5))
        capture("20-会员管理")
        app.navigationBars.buttons.firstMatch.tap()
        let custom = app.buttons["model.open"]
        reveal(custom, in: app)
        custom.tap()
        XCTAssertTrue(app.buttons["model.save"].waitForExistence(timeout: 8))
        capture("21-自定义模型")
        let prompt = app.buttons["编辑提示词"]
        reveal(prompt, in: app)
        prompt.tap()
        XCTAssertTrue(app.segmentedControls.buttons["拍照识别"].waitForExistence(timeout: 5))
        capture("22-编辑提示词")
        app.navigationBars.buttons.firstMatch.tap()
        let debug = app.buttons["model.debug"]
        reveal(debug, in: app)
        debug.tap()
        XCTAssertTrue(app.segmentedControls.buttons["拍照"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["拍照"].tap()
        capture("23-调试模型")
        app.segmentedControls.buttons["代谢"].tap()
        let sample = app.buttons["填入示例资料"]
        reveal(sample, in: app)
        sample.tap()
        let run = app.buttons["debug.run"]
        reveal(run, in: app)
        run.tap()
        XCTAssertTrue(app.staticTexts["格式校验通过"].waitForExistence(timeout: 15))
        capture("23b-模型调试结果")
        app.navigationBars.buttons.firstMatch.tap()
        let balance = app.buttons["model.balance"]
        reveal(balance, in: app)
        balance.tap()
        XCTAssertTrue(app.staticTexts["¥12.50"].waitForExistence(timeout: 8))
        capture("24-查询余额")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let appearance = app.buttons["appearance.open"]
        reveal(appearance, in: app)
        appearance.tap()
        let blue = app.buttons["skin.blue"]
        reveal(blue, in: app)
        blue.tap()
        let apply = app.buttons["应用皮肤"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        capture("25-雾蓝简约预览")
        apply.tap()
        XCTAssertTrue(blue.waitForExistence(timeout: 8))
    }

    private func verifyPhotoCancellationAndReview(in app: XCUIApplication) {
        app.buttons["meal.photo"].tap()
        XCTAssertTrue(app.buttons["photo.library"].waitForExistence(timeout: 8))
        verifyActionPair(app.buttons["photo.camera"], app.buttons["photo.library"])
        capture("11a-拍照选图")
        let start = app.buttons["photo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        let cancel = app.buttons["analysis.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        reveal(cancel, in: app)
        capture("11-AI处理进度")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["photo.cancelled"].waitForExistence(timeout: 10))
        reveal(start, in: app)
        start.tap()
        let confirmation = app.navigationBars["确认食物信息"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["photo.result"].exists)
        let proceed = app.buttons["confirmation.continue"]
        XCTAssertFalse(proceed.isEnabled)
        let rice = app.buttons["糙米"]
        reveal(rice, in: app)
        rice.tap()
        let uncertain = app.buttons["confirmation.unknown.1"]
        reveal(uncertain, in: app)
        uncertain.tap()
        capture("11b-确认食物信息")
        XCTAssertTrue(proceed.isEnabled)
        proceed.tap()
        let result = app.staticTexts["photo.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["已按确认的糙米重新估算。"].exists)
        capture("12-照片分析结果")
        let review = app.buttons["photo.review"]
        reveal(review, in: app)
        review.tap()
        XCTAssertTrue(app.buttons["meal.save"].waitForExistence(timeout: 5))
        capture("13-AI食物核对")
        app.navigationBars["核对食物与份量"].buttons["取消"].tap()
        app.navigationBars["拍照记餐"].buttons["关闭"].tap()
        XCTAssertEqual(app.staticTexts["intake.total"].label, "125", "Unconfirmed AI results must not be saved")
    }

    private func verifyRepeatedNavigation(in app: XCUIApplication) {
        for _ in 0..<6 {
            app.tabBars.buttons["趋势"].tap()
            for mode in ["周", "月", "年"] {
                let picker = app.segmentedControls["trends.period"]
                XCTAssertTrue(picker.waitForExistence(timeout: 5))
                picker.buttons[mode].tap()
                let range = app.staticTexts["trends.range"]
                let format = mode == "周" ? "label CONTAINS %@" : "label ENDSWITH %@"
                let expected = mode == "周" ? "—" : mode
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, expected), object: range)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "Selected period and rendered data must agree")
            }
            app.tabBars.buttons["今日"].tap()
            XCTAssertTrue(app.buttons["meal.manual"].waitForExistence(timeout: 5))
            app.tabBars.buttons["我的"].tap()
            XCTAssertTrue(app.staticTexts["app.build"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["趋势"].tap()
        capture("14-730天历史数据与连续切换")
    }

    private func login(_ name: String, registering: Bool = false, in app: XCUIApplication) {
        let mode = app.buttons["service.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 8))
        if !registering { mode.tap() }
        if registering {
            let addressEntry = app.buttons["service.address.open"]
            reveal(addressEntry, in: app)
            addressEntry.tap()
            let address = app.textFields["service.address"]
            XCTAssertTrue(address.waitForExistence(timeout: 8))
            XCTAssertEqual(address.value as? String, "http://localhost:8787")
            capture("00b-服务器地址")
            let saveAddress = app.buttons["service.address.save"]
            XCTAssertTrue(saveAddress.isEnabled)
            saveAddress.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: address)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        } else {
            capture("00c-登录")
        }
        let username = app.textFields["service.username"]
        reveal(username, in: app)
        username.tap()
        username.typeText(name)
        let password = app.secureTextFields["service.password"]
        reveal(password, in: app)
        password.tap()
        password.typeText(registering ? "test-password-only" : "test-password-only\n")
        if registering {
            let confirm = app.secureTextFields["service.confirm"]
            reveal(confirm, in: app)
            confirm.tap()
            confirm.typeText("test-password-only\n")
        }
        let submit = app.buttons["service.save"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        reveal(submit, in: app)
        submit.tap()
        let signedIn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: submit)
        XCTAssertEqual(XCTWaiter.wait(for: [signedIn], timeout: 15), .completed, "NAS account login failed")
    }

    private func verifyActionPair(_ first: XCUIElement, _ second: XCUIElement) {
        XCTAssertTrue(first.exists && second.exists)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, 50, accuracy: 1)
        XCTAssertEqual(second.frame.height, 50, accuracy: 1)
        XCTAssertEqual(second.frame.minX - first.frame.maxX, 12, accuracy: 1)
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
